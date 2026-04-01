import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // 使用 Base64 编码传递内容，彻底解决 JS 转义和特殊字符问题
        let base64Markdown = Data(markdown.utf8).base64EncodedString()
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            <script>
                marked.setOptions({
                    breaks: true,
                    gfm: true,
                    headerIds: true
                });

                window.MathJax = {
                    tex: { inlineMath: [['$', '$']], displayMath: [['$$', '$$']], processEscapes: true },
                    options: { enableMenu: false },
                    startup: { typeset: false }
                };
            </script>
            <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                    font-size: 15px; line-height: 1.8;
                    color: \(NSColor.textColor.hexString);
                    background-color: transparent; padding: 20px;
                    overflow-x: hidden;
                }
                h1, h2, h3 { border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; margin-top: 1.5em; }
                p { margin-bottom: 1.2em; }
                strong { font-weight: bold; color: \(NSColor.labelColor.hexString); }
                code { background: rgba(175,184,193,0.2); padding: 2px 5px; border-radius: 4px; font-family: monospace; }
                blockquote { border-left: 4px solid #dfe2e5; color: #6a737d; padding-left: 1em; margin: 0 0 1.2em 0; }
                img { max-width: 100%; height: auto; }
            </style>
        </head>
        <body>
            <div id="content">正在深度解析...</div>
            <script>
                function doRender() {
                    try {
                        let b64 = "\(base64Markdown)";
                        let binString = window.atob(b64);
                        let bytes = new Uint8Array(binString.length);
                        for (let i = 0; i < binString.length; i++) {
                            bytes[i] = binString.charCodeAt(i);
                        }
                        let raw = new TextDecoder().decode(bytes);
                        
                        // 预处理
                        let fixed = raw.replace(/\\*\\*\\s+/g, "**").replace(/\\s+\\*\\*/g, "**");
                        
                        document.getElementById('content').innerHTML = marked.parse(fixed);
                        
                        if (window.MathJax && window.MathJax.typeset) {
                            window.MathJax.typeset();
                        }
                    } catch (e) {
                        document.getElementById('content').innerHTML = "渲染错误: " + e.message;
                    }
                }
                
                window.onload = doRender;
                setTimeout(doRender, 100);
            </script>
        </body>
        </html>
        """
        nsView.loadHTMLString(html, baseURL: nil)
    }
}

extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02x%02x%02x", Int(rgbColor.redComponent * 255), Int(rgbColor.greenComponent * 255), Int(rgbColor.blueComponent * 255))
    }
}
