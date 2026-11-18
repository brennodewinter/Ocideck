{{flutter_js}}
{{flutter_build_config}}

// Keep the loader external: the page's CSP permits neither inline JS nor eval.
// Feature detection still selects the JS fallback on older browser engines.
performance.mark('ocideck:bootstrap');
// runApp's JS promise starts main(); it does not wait for Dart's first paint.
window.addEventListener('flutter-first-frame', function () {
  performance.mark('ocideck:first-frame');
  performance.measure('ocideck:startup', 'ocideck:bootstrap', 'ocideck:first-frame');
  performance.measure('ocideck:app-init', 'ocideck:engine', 'ocideck:first-frame');
}, { once: true });
_flutter.loader.load({
  config: {
    wasmAllowList: { blink: true, webkit: true, gecko: true },
  },
  onEntrypointLoaded: async function (engineInitializer) {
    performance.mark('ocideck:entrypoint');
    const appRunner = await engineInitializer.initializeEngine();
    performance.mark('ocideck:engine');
    await appRunner.runApp();
    performance.mark('ocideck:main-started');
    performance.measure('ocideck:engine-init', 'ocideck:entrypoint', 'ocideck:engine');
  },
});
