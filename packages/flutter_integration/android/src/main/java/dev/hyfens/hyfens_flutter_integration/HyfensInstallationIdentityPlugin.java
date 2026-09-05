package dev.hyfens.hyfens_flutter_integration;

import android.content.Context;
import android.os.Build;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyInfo;
import android.security.keystore.KeyProperties;
import android.security.keystore.StrongBoxUnavailableException;
import android.util.Base64;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.ProviderException;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECFieldFp;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECPoint;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/** Native installation identity and P-256 signing plugin. */
public final class HyfensInstallationIdentityPlugin
    implements FlutterPlugin, MethodCallHandler {
  // All engines in this app process share one Keystore alias and marker.
  private static final Object IDENTITY_LOCK = new Object();

  private volatile MethodChannel channel;
  private volatile Context context;
  private volatile ExecutorService executor;

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    executor = Executors.newSingleThreadExecutor();
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    if ("getIdentity".equals(call.method)) {
      submit(result, () -> identityMap(requireContext()));
      return;
    }
    if ("sign".equals(call.method)) {
      final byte[] message;
      try {
        message = messageBytes(call.arguments);
      } catch (InvalidMessageException error) {
        result.error(ERROR_INVALID_MESSAGE, error.getMessage(), null);
        return;
      }
      submit(result, () -> sign(requireContext(), message));
      return;
    }
    result.notImplemented();
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    MethodChannel currentChannel = channel;
    if (currentChannel != null) {
      currentChannel.setMethodCallHandler(null);
    }
    channel = null;
    ExecutorService currentExecutor = executor;
    if (currentExecutor != null) {
      currentExecutor.shutdownNow();
    }
    executor = null;
    context = null;
  }

  private Context requireContext() throws KeyUnavailableException {
    Context currentContext = context;
    if (currentContext == null) {
      throw new KeyUnavailableException("Plugin is not attached to an engine");
    }
    return currentContext;
  }

  private void submit(Result result, Callable<Object> operation) {
    ExecutorService worker = executor;
    if (worker == null) {
      result.error(ERROR_KEY_UNAVAILABLE, ERROR_MESSAGE, null);
      return;
    }
    try {
      worker.execute(() -> {
        try {
          result.success(operation.call());
        } catch (InvalidMessageException error) {
          result.error(ERROR_INVALID_MESSAGE, error.getMessage(), null);
        } catch (KeyUnavailableException error) {
          result.error(ERROR_KEY_UNAVAILABLE, ERROR_MESSAGE, null);
        } catch (Throwable error) {
          // A native failure is returned to Dart instead of escaping the
          // channel callback and affecting the host application.
          result.error(ERROR_KEY_UNAVAILABLE, ERROR_MESSAGE, null);
        }
      });
    } catch (RejectedExecutionException error) {
      result.error(ERROR_KEY_UNAVAILABLE, ERROR_MESSAGE, null);
    }
  }

  private Map<String, Object> identityMap(Context applicationContext)
      throws KeyUnavailableException {
    IdentityRecord record = loadOrCreateRecord(applicationContext);
    Map<String, Object> result = new HashMap<>();
    result.put("installationId", record.installationId);
    result.put("keyId", record.keyId);
    result.put("publicKey", record.publicKey);
    result.put("storageProtection", record.storageProtection);
    return result;
  }

  private byte[] sign(Context applicationContext, byte[] message)
      throws KeyUnavailableException {
    synchronized (IDENTITY_LOCK) {
      IdentityRecord record = loadOrCreateRecordLocked(applicationContext);
      try {
        Signature signer = Signature.getInstance("SHA256withECDSA");
        signer.initSign(record.keyPair.getPrivate());
        signer.update(message);
        return derToP1363(signer.sign());
      } catch (KeyUnavailableException error) {
        throw error;
      } catch (GeneralSecurityException error) {
        throw new KeyUnavailableException("Could not sign with installation key", error);
      }
    }
  }

  private IdentityRecord loadOrCreateRecord(Context applicationContext)
      throws KeyUnavailableException {
    synchronized (IDENTITY_LOCK) {
      return loadOrCreateRecordLocked(applicationContext);
    }
  }

  private IdentityRecord loadOrCreateRecordLocked(Context applicationContext)
      throws KeyUnavailableException {
    try {
      KeyStore keyStore = keyStore();
      Marker marker = readMarker(applicationContext);
      if (marker == null) {
        deleteKey(keyStore);
        KeyPair keyPair = generateKeyPair(keyStore);
        byte[] publicKey = publicKeyBytes(keyPair.getPublic());
        String keyId = sha256Hex(publicKey);
        String installationId = newInstallationId();
        IdentityRecord record = record(installationId, keyId, publicKey, keyPair);
        try {
          writeMarker(
              applicationContext,
              new Marker(installationId, keyId));
        } catch (Throwable error) {
          try {
            deleteKey(keyStore);
          } catch (Throwable ignored) {
            // The operation remains unavailable; never return an identity
            // without a durable marker binding it.
          }
          throw new KeyUnavailableException(
              "Could not persist installation marker", error);
        }
        return record;
      }

      KeyPair keyPair = existingKeyPair(keyStore);
      byte[] publicKey = publicKeyBytes(keyPair.getPublic());
      String keyId = sha256Hex(publicKey);
      if (!marker.keyId.equals(keyId)) {
        throw new KeyUnavailableException("Installation key binding changed");
      }
      return record(marker.installationId, keyId, publicKey, keyPair);
    } catch (KeyUnavailableException error) {
      throw error;
    } catch (Throwable error) {
      throw new KeyUnavailableException("Could not load installation key", error);
    }
  }

  private IdentityRecord record(
      String installationId,
      String keyId,
      byte[] publicKey,
      KeyPair keyPair)
      throws GeneralSecurityException {
    String protection = isHardwareBacked(keyPair.getPrivate())
        ? STORAGE_HARDWARE_BACKED
        : STORAGE_PLATFORM_PROTECTED;
    return new IdentityRecord(
        installationId,
        keyId,
        publicKey,
        protection,
        keyPair);
  }

  private KeyStore keyStore() throws GeneralSecurityException, IOException {
    KeyStore keyStore = KeyStore.getInstance(ANDROID_KEYSTORE);
    keyStore.load(null);
    return keyStore;
  }

  private KeyPair existingKeyPair(KeyStore keyStore)
      throws GeneralSecurityException, KeyUnavailableException {
    java.security.Key key = keyStore.getKey(KEY_ALIAS, null);
    if (!(key instanceof PrivateKey)) {
      throw new KeyUnavailableException("Installation private key is missing");
    }
    java.security.cert.Certificate certificate = keyStore.getCertificate(KEY_ALIAS);
    if (certificate == null) {
      throw new KeyUnavailableException("Installation public key is missing");
    }
    return new KeyPair(certificate.getPublicKey(), (PrivateKey) key);
  }

  private KeyPair generateKeyPair(KeyStore keyStore)
      throws GeneralSecurityException, KeyUnavailableException {
    KeyPairGenerator generator = KeyPairGenerator.getInstance(
        KeyProperties.KEY_ALGORITHM_EC,
        ANDROID_KEYSTORE);
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      try {
        generator.initialize(keySpec(true));
        return generator.generateKeyPair();
      } catch (StrongBoxUnavailableException error) {
        // StrongBox is a preference. An explicit non-StrongBox retry still
        // keeps the private key non-exportable.
        deleteKey(keyStore);
      } catch (ProviderException error) {
        // Some providers report unavailable StrongBox through ProviderException.
        deleteKey(keyStore);
      }
    }
    try {
      generator.initialize(keySpec(false));
      return generator.generateKeyPair();
    } catch (GeneralSecurityException error) {
      throw new KeyUnavailableException("Could not create installation key", error);
    } catch (ProviderException error) {
      throw new KeyUnavailableException("Could not create installation key", error);
    }
  }

  private KeyGenParameterSpec keySpec(boolean strongBox) {
    KeyGenParameterSpec.Builder builder = new KeyGenParameterSpec.Builder(
        KEY_ALIAS,
        KeyProperties.PURPOSE_SIGN);
    builder.setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"));
    builder.setDigests(KeyProperties.DIGEST_SHA256);
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      builder.setIsStrongBoxBacked(strongBox);
    }
    return builder.build();
  }

  @SuppressWarnings("deprecation")
  private boolean isHardwareBacked(PrivateKey privateKey)
      throws GeneralSecurityException {
    KeyFactory factory = KeyFactory.getInstance(
        KeyProperties.KEY_ALGORITHM_EC,
        ANDROID_KEYSTORE);
    KeyInfo info = factory.getKeySpec(privateKey, KeyInfo.class);
    return info.isInsideSecureHardware();
  }

  private void deleteKey(KeyStore keyStore) throws GeneralSecurityException {
    if (keyStore.containsAlias(KEY_ALIAS)) {
      keyStore.deleteEntry(KEY_ALIAS);
    }
  }

  private File markerFile(Context applicationContext) {
    return new File(
        new File(applicationContext.getNoBackupFilesDir(), MARKER_DIRECTORY),
        MARKER_NAME);
  }

  private Marker readMarker(Context applicationContext)
      throws KeyUnavailableException {
    File file = markerFile(applicationContext);
    if (!file.exists()) {
      return null;
    }
    final String contents;
    try {
      contents = readAscii(file);
    } catch (IOException error) {
      throw new KeyUnavailableException("Could not read installation marker", error);
    }
    String[] parts = contents.split("\\n", -1);
    if (parts.length != 2) {
      throw new KeyUnavailableException("Installation marker is malformed");
    }
    String installationId = parts[0];
    String keyId = parts[1];
    byte[] decodedInstallationId;
    try {
      decodedInstallationId = Base64.decode(
          installationId,
          Base64.URL_SAFE | Base64.NO_PADDING);
    } catch (IllegalArgumentException error) {
      decodedInstallationId = null;
    }
    String canonicalInstallationId = decodedInstallationId == null
        ? null
        : Base64.encodeToString(
            decodedInstallationId,
            Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
    if (!INSTALLATION_ID_PATTERN.matcher(installationId).matches()
        || decodedInstallationId == null
        || decodedInstallationId.length != 32
        || !installationId.equals(canonicalInstallationId)
        || !KEY_ID_PATTERN.matcher(keyId).matches()) {
      throw new KeyUnavailableException("Installation marker is malformed");
    }
    return new Marker(installationId, keyId);
  }

  private String readAscii(File file) throws IOException {
    try (FileInputStream input = new FileInputStream(file);
         ByteArrayOutputStream output = new ByteArrayOutputStream()) {
      byte[] buffer = new byte[256];
      int count;
      while ((count = input.read(buffer)) != -1) {
        output.write(buffer, 0, count);
      }
      return output.toString(StandardCharsets.US_ASCII.name());
    }
  }

  private void writeMarker(Context applicationContext, Marker marker)
      throws IOException, KeyUnavailableException {
    File directory = markerFile(applicationContext).getParentFile();
    if (directory == null) {
      throw new KeyUnavailableException("Installation marker directory is unavailable");
    }
    if (!directory.exists() && !directory.mkdirs()) {
      throw new KeyUnavailableException("Could not create installation marker directory");
    }
    File file = markerFile(applicationContext);
    File temporary = new File(directory, MARKER_NAME + ".tmp");
    try {
      try (FileOutputStream output = new FileOutputStream(temporary)) {
        output.write(
            (marker.installationId + "\n" + marker.keyId)
                .getBytes(StandardCharsets.US_ASCII));
        output.flush();
        output.getFD().sync();
      }
      if (!temporary.renameTo(file)) {
        throw new KeyUnavailableException("Could not commit installation marker");
      }
    } finally {
      if (temporary.exists()) {
        temporary.delete();
      }
    }
  }

  private String newInstallationId() {
    byte[] random = new byte[32];
    new java.security.SecureRandom().nextBytes(random);
    return Base64.encodeToString(
        random,
        Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
  }

  private byte[] publicKeyBytes(java.security.PublicKey publicKey)
      throws KeyUnavailableException {
    if (!(publicKey instanceof ECPublicKey)) {
      throw new KeyUnavailableException("Installation key is not EC");
    }
    ECPublicKey ecKey = (ECPublicKey) publicKey;
    java.security.spec.ECParameterSpec parameters = ecKey.getParams();
    if (!(parameters.getCurve().getField() instanceof ECFieldFp)) {
      throw new KeyUnavailableException("Installation key is not prime-field P-256");
    }
    ECFieldFp field = (ECFieldFp) parameters.getCurve().getField();
    ECPoint generator = parameters.getGenerator();
    if (!P256_P.equals(field.getP())
        || !P256_A.equals(parameters.getCurve().getA())
        || !P256_B.equals(parameters.getCurve().getB())
        || !P256_GX.equals(generator.getAffineX())
        || !P256_GY.equals(generator.getAffineY())
        || !P256_N.equals(parameters.getOrder())
        || parameters.getCofactor() != 1) {
      throw new KeyUnavailableException("Installation key is not P-256");
    }
    ECPoint point = ecKey.getW();
    byte[] x = fixedUnsigned(point.getAffineX());
    byte[] y = fixedUnsigned(point.getAffineY());
    byte[] result = new byte[65];
    result[0] = 0x04;
    System.arraycopy(x, 0, result, 1, 32);
    System.arraycopy(y, 0, result, 33, 32);
    return result;
  }

  private byte[] fixedUnsigned(BigInteger value) throws KeyUnavailableException {
    if (value.signum() < 0 || value.compareTo(P256_P) >= 0) {
      throw new KeyUnavailableException("Installation public point is out of range");
    }
    byte[] encoded = value.toByteArray();
    int offset = encoded.length == 33 && encoded[0] == 0 ? 1 : 0;
    if (encoded.length - offset > 32) {
      throw new KeyUnavailableException("Installation public point is malformed");
    }
    byte[] result = new byte[32];
    System.arraycopy(
        encoded,
        offset,
        result,
        32 - (encoded.length - offset),
        encoded.length - offset);
    return result;
  }

  private String sha256Hex(byte[] bytes) throws KeyUnavailableException {
    try {
      byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
      StringBuilder result = new StringBuilder(digest.length * 2);
      for (byte value : digest) {
        result.append(HEX[(value >>> 4) & 0x0f]);
        result.append(HEX[value & 0x0f]);
      }
      return result.toString();
    } catch (GeneralSecurityException error) {
      throw new KeyUnavailableException("SHA-256 is unavailable", error);
    }
  }

  private byte[] messageBytes(Object arguments) throws InvalidMessageException {
    if (!(arguments instanceof Map)) {
      throw new InvalidMessageException("Signing arguments are not a map");
    }
    Object value = ((Map<?, ?>) arguments).get("message");
    if (value instanceof byte[]) {
      byte[] message = (byte[]) value;
      if (message.length > MAX_MESSAGE_LENGTH) {
        throw new InvalidMessageException("Signing message exceeds the 16 KiB limit");
      }
      return message;
    }
    if (!(value instanceof List)) {
      throw new InvalidMessageException("Signing message is not bytes");
    }
    List<?> values = (List<?>) value;
    byte[] result = new byte[values.size()];
    for (int index = 0; index < values.size(); index++) {
      Object item = values.get(index);
      if (!(item instanceof Integer)) {
        throw new InvalidMessageException("Signing message is not bytes");
      }
      int byteValue = (Integer) item;
      if (byteValue < 0 || byteValue > 0xff) {
        throw new InvalidMessageException("Signing message is not bytes");
      }
      result[index] = (byte) byteValue;
    }
    if (result.length > MAX_MESSAGE_LENGTH) {
      throw new InvalidMessageException("Signing message exceeds the 16 KiB limit");
    }
    return result;
  }

  private byte[] derToP1363(byte[] signature) throws KeyUnavailableException {
    DerReader reader = new DerReader(signature);
    reader.requireTag(0x30);
    int sequenceLength = reader.readLength();
    if (sequenceLength != reader.remaining()) {
      throw new KeyUnavailableException("ECDSA signature has invalid DER length");
    }
    byte[] rValue = reader.readInteger();
    byte[] sValue = reader.readInteger();
    if (reader.remaining() != 0) {
      throw new KeyUnavailableException("ECDSA signature has trailing DER data");
    }
    byte[] result = new byte[64];
    System.arraycopy(rValue, 0, result, 0, 32);
    System.arraycopy(sValue, 0, result, 32, 32);
    return result;
  }

  private static final class DerReader {
    private final byte[] bytes;
    private int offset;

    DerReader(byte[] bytes) {
      this.bytes = bytes;
    }

    int remaining() {
      return bytes.length - offset;
    }

    void requireTag(int expected) throws KeyUnavailableException {
      if (offset >= bytes.length || (bytes[offset++] & 0xff) != expected) {
        throw new KeyUnavailableException("ECDSA signature has invalid DER tag");
      }
    }

    int readLength() throws KeyUnavailableException {
      if (offset >= bytes.length) {
        throw new KeyUnavailableException("ECDSA signature has truncated DER length");
      }
      int first = bytes[offset++] & 0xff;
      if ((first & 0x80) == 0) {
        return first;
      }
      int count = first & 0x7f;
      if (count == 0 || count > 2 || offset + count > bytes.length) {
        throw new KeyUnavailableException("ECDSA signature has invalid DER length");
      }
      if (bytes[offset] == 0) {
        throw new KeyUnavailableException("ECDSA signature has non-minimal DER length");
      }
      int length = 0;
      for (int index = 0; index < count; index++) {
        length = (length << 8) | (bytes[offset++] & 0xff);
      }
      if (length < 128) {
        throw new KeyUnavailableException("ECDSA signature has non-minimal DER length");
      }
      return length;
    }

    byte[] readInteger() throws KeyUnavailableException {
      requireTag(0x02);
      int length = readLength();
      if (length == 0 || length > 33 || length > remaining()) {
        throw new KeyUnavailableException("ECDSA signature integer is malformed");
      }
      byte[] integer = new byte[length];
      System.arraycopy(bytes, offset, integer, 0, length);
      offset += length;
      if ((integer[0] & 0x80) != 0
          || (length > 1 && integer[0] == 0 && (integer[1] & 0x80) == 0)) {
        throw new KeyUnavailableException(
            "ECDSA signature integer is not canonical DER");
      }
      BigInteger value = new BigInteger(1, integer);
      if (value.signum() <= 0 || value.compareTo(P256_N) >= 0) {
        throw new KeyUnavailableException("ECDSA signature integer is out of range");
      }
      return fixedScalar(value);
    }

    private byte[] fixedScalar(BigInteger value) throws KeyUnavailableException {
      byte[] encoded = value.toByteArray();
      int offset = encoded.length == 33 && encoded[0] == 0 ? 1 : 0;
      if (encoded.length - offset > 32) {
        throw new KeyUnavailableException("ECDSA signature integer is too large");
      }
      byte[] result = new byte[32];
      System.arraycopy(
          encoded,
          offset,
          result,
          32 - (encoded.length - offset),
          encoded.length - offset);
      return result;
    }
  }

  private static final class Marker {
    final String installationId;
    final String keyId;

    Marker(String installationId, String keyId) {
      this.installationId = installationId;
      this.keyId = keyId;
    }
  }

  private static final class IdentityRecord {
    final String installationId;
    final String keyId;
    final byte[] publicKey;
    final String storageProtection;
    final KeyPair keyPair;

    IdentityRecord(
        String installationId,
        String keyId,
        byte[] publicKey,
        String storageProtection,
        KeyPair keyPair) {
      this.installationId = installationId;
      this.keyId = keyId;
      this.publicKey = publicKey;
      this.storageProtection = storageProtection;
      this.keyPair = keyPair;
    }
  }

  private static class InvalidMessageException extends Exception {
    private static final long serialVersionUID = 1L;

    InvalidMessageException(String message) {
      super(message);
    }
  }

  private static class KeyUnavailableException extends Exception {
    private static final long serialVersionUID = 1L;

    KeyUnavailableException(String message) {
      super(message);
    }

    KeyUnavailableException(String message, Throwable cause) {
      super(message, cause);
    }
  }

  private static final String ANDROID_KEYSTORE = "AndroidKeyStore";
  private static final String CHANNEL_NAME = "hyfens/installation_identity";
  private static final String KEY_ALIAS = "hyfens.installation_identity.p256";
  private static final String MARKER_DIRECTORY = "hyfens/installation_identity";
  private static final String MARKER_NAME = "installation.marker";
  private static final String ERROR_KEY_UNAVAILABLE = "keyUnavailable";
  private static final String ERROR_INVALID_MESSAGE = "invalidMessage";
  private static final String ERROR_MESSAGE = "Installation identity is unavailable.";
  private static final int MAX_MESSAGE_LENGTH = 16 * 1024;
  private static final String STORAGE_HARDWARE_BACKED = "hardwareBacked";
  private static final String STORAGE_PLATFORM_PROTECTED = "platformProtected";
  private static final java.util.regex.Pattern KEY_ID_PATTERN =
      java.util.regex.Pattern.compile("[0-9a-f]{64}");
  private static final java.util.regex.Pattern INSTALLATION_ID_PATTERN =
      java.util.regex.Pattern.compile("[A-Za-z0-9_-]{43}");
  private static final char[] HEX = "0123456789abcdef".toCharArray();
  private static final BigInteger P256_P = new BigInteger(
      "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF", 16);
  private static final BigInteger P256_A = P256_P.subtract(BigInteger.valueOf(3));
  private static final BigInteger P256_B = new BigInteger(
      "5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B", 16);
  private static final BigInteger P256_GX = new BigInteger(
      "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296", 16);
  private static final BigInteger P256_GY = new BigInteger(
      "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5", 16);
  private static final BigInteger P256_N = new BigInteger(
      "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", 16);
}
