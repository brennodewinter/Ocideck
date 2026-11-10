// Exercises the actual vendored GTK/WebKit offscreen controller with the HTML
// emitted by MermaidRenderService. Run under Xvfb; no visible window is needed.
#include "my_webview.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  gtk_init(&argc, &argv);
  std::ifstream input(argv[1]);
  std::string html((std::istreambuf_iterator<char>(input)), {});
  if (html.empty()) return 2;
  auto* loop = g_main_loop_new(nullptr, FALSE);
  MyWebView* view = nullptr;
  int received = 0;
  bool passed = false;
  MyWebViewCreateParams params;
  params.offscreen = true;
  params.onNavigationRequest = [](int, const gchar*, bool) {};
  params.onPageStarted = [](const gchar*) {};
  params.onPageFinished = [](const gchar*) {};
  params.onHttpError = [](const gchar*, int) {};
  params.onSslAuthError = [](const gchar*) {};
  params.onWebResourceError = [](const gchar*, int, const gchar*) {};
  params.onUrlChange = [](const gchar*) {};
  params.onPageTitleChanged = [](const gchar*) {};
  params.onFullScreenChanged = [](bool) {};
  params.onAskPermission = [](const gchar*, int, int) {};
  params.onWebMessageReceived = [&](gchar*, gchar* message) {
    const std::string text(message ? message : "");
    if (text.find("setup-ok") != std::string::npos) {
      view->runJavascript(const_cast<gchar*>(
          "window.__renderMermaid('graph TD; Aanvraag-->Besluit;', 1);"
          "window.__renderMath('E=mc^2', 2);"
          "window.__renderMermaid('gantt\\n dateFormat YYYY-MM-DD\\n section Proef\\n Taak :2026-11-10, 1d',3);"));
    } else if (text.find("svg") != std::string::npos &&
               text.find("<svg") != std::string::npos) {
      if (++received == 3) { passed = true; g_main_loop_quit(loop); }
    } else if (text.find("error") != std::string::npos) {
      std::cerr << "renderer reported an error\n";
      g_main_loop_quit(loop);
    }
  };
  // Offscreen mode must work without an editor GTK container at all.
  auto owned = std::make_unique<MyWebView>(nullptr, params, nullptr);
  view = owned.get();
  view->enableJavascript(true);
  view->addScriptChannelByName(const_cast<gchar*>("MermaidChannel"));
  view->loadHtmlString(html.data(), nullptr);
  g_timeout_add_seconds(45, [](gpointer data) -> gboolean {
    g_main_loop_quit(static_cast<GMainLoop*>(data)); return G_SOURCE_REMOVE;
  }, loop);
  g_main_loop_run(loop);
  std::cout << "offscreen SVG responses: " << received << "/3\n";
  owned.reset();
  g_main_loop_unref(loop);
  return passed ? 0 : 1;
}
