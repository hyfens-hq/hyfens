// The Docker entrypoint replaces this value in its ephemeral web root.
// Keeping a source default also makes the dependency-free dashboard usable
// from the local Python server and from a plain checkout.
window.__HYFENS_RUNTIME_CONFIG__ = { apiBase: '' };
