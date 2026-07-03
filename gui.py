#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# gui.py - video2x-mac-unofficial のローカルWeb GUI
#   video2x.sh をそのまま呼び出し、ブラウザでファイル選択・設定・進捗表示を行う。
#   依存は標準ライブラリのみ。起動: python3 gui.py
#
import http.server, socketserver, subprocess, urllib.parse, json, os, threading, webbrowser, re

HERE   = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "video2x.sh")
PORT   = 8765
ANSI   = re.compile(r'\x1b\[[0-9;]*m')

PAGE = r"""<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>video2x-mac-unofficial</title>
<link rel="icon" type="image/svg+xml" href="/favicon.svg">
<style>
  :root{--bg:#0f1216;--card:#171c23;--line:#283039;--fg:#e6edf3;--mut:#8b97a4;--acc:#4cc2ff;--ok:#3fb950;--err:#f85149}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 -apple-system,BlinkMacSystemFont,"Hiragino Kaku Gothic ProN","Segoe UI",sans-serif}
  .wrap{max-width:760px;margin:0 auto;padding:24px}
  h1{font-size:18px;margin:0 0 2px} .sub{color:var(--mut);font-size:12px;margin-bottom:18px}
  .card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:18px;margin-bottom:16px}
  label{display:block;font-size:12px;color:var(--mut);margin:0 0 4px}
  .row{display:flex;gap:14px;flex-wrap:wrap}
  .row>div{flex:1;min-width:120px}
  input[type=text],select,input[type=number]{width:100%;background:#0d1117;border:1px solid var(--line);color:var(--fg);border-radius:8px;padding:8px 10px;font:inherit}
  .file{display:flex;gap:8px}
  .file input{flex:1}
  button{background:var(--acc);color:#04243a;border:0;border-radius:8px;padding:9px 14px;font:600 14px/1 inherit;cursor:pointer}
  button.ghost{background:#222a33;color:var(--fg);border:1px solid var(--line)}
  button:disabled{opacity:.5;cursor:not-allowed}
  .toggle{display:flex;align-items:center;gap:8px;margin-top:22px}
  .toggle input{width:auto}
  #run{width:100%;padding:12px;font-size:15px;margin-top:4px}
  .bar{position:relative;height:10px;background:#0d1117;border-radius:6px;overflow:hidden;margin:10px 0}
  .bar>i{display:block;height:100%;width:0;background:var(--acc);transition:width .3s}
  .bar.run>i{min-width:8%;background-image:linear-gradient(45deg,rgba(255,255,255,.30) 25%,transparent 25%,transparent 50%,rgba(255,255,255,.30) 50%,rgba(255,255,255,.30) 75%,transparent 75%,transparent);background-size:22px 22px;animation:stripe .8s linear infinite}
  @keyframes stripe{from{background-position:0 0}to{background-position:22px 0}}
  #step{font-size:13px;color:var(--fg);margin-bottom:4px}
  pre{background:#0d1117;border:1px solid var(--line);border-radius:8px;padding:10px;max-height:240px;overflow:auto;font:12px/1.45 ui-monospace,Menlo,monospace;white-space:pre-wrap;margin:0}
  .done{color:var(--ok)} .bad{color:var(--err)}
  .lang{float:right} .lang button{background:none;border:1px solid var(--line);color:var(--mut);padding:3px 8px;font-size:12px;border-radius:6px}
  .lang button.on{color:var(--fg);border-color:var(--acc)}
  .muted{color:var(--mut);font-size:12px}
  a{color:var(--acc)}
</style>
</head>
<body><div class="wrap">
  <div class="lang">
    <button data-lang="ja" class="on">日本語</button>
    <button data-lang="zh">中文</button>
    <button data-lang="en">EN</button>
  </div>
  <h1>video2x-mac-unofficial</h1>
  <div class="sub" data-i18n="tagline">超解像アップスケール＋フレーム補間（ローカル / Apple Silicon）</div>

  <div class="card">
    <label data-i18n="input">入力動画</label>
    <div class="file">
      <input type="text" id="path" placeholder="/path/to/video.mp4">
      <button class="ghost" id="pick" data-i18n="browse">選択…</button>
    </div>

    <div class="row" style="margin-top:14px">
      <div>
        <label data-i18n="model">モデル</label>
        <select id="m">
          <option value="anime" data-i18n="m_anime">anime（線がくっきり・既定）</option>
          <option value="photo" data-i18n="m_photo">photo（実写寄り）</option>
          <option value="anime-video" data-i18n="m_av">anime-video（柔らかい）</option>
        </select>
      </div>
      <div>
        <label data-i18n="scale">アップスケール倍率</label>
        <select id="s"><option>2</option><option>3</option><option>4</option></select>
      </div>
      <div>
        <label data-i18n="factor">補間倍率</label>
        <input type="number" id="f" value="2" min="2" step="1">
      </div>
      <div>
        <label data-i18n="cap">解像度上限(長辺px, 0=無制限)</label>
        <input type="number" id="x" value="3840" min="0" step="1">
      </div>
    </div>

    <div class="row">
      <div class="toggle"><input type="checkbox" id="u" checked><label style="margin:0" data-i18n="t_up">アップスケール</label></div>
      <div class="toggle"><input type="checkbox" id="r" checked><label style="margin:0" data-i18n="t_interp">フレーム補間</label></div>
    </div>

    <button id="run" data-i18n="run">実行</button>
  </div>

  <div class="card">
    <div id="step" data-i18n="idle">待機中</div>
    <div class="bar" id="bar"><i id="barfill"></i></div>
    <pre id="log"></pre>
    <div id="result" class="muted" style="margin-top:10px"></div>
  </div>
  <div class="muted">video2x.sh を呼び出しています / wraps <code>video2x.sh</code></div>
</div>
<script>
const I18N = {
  ja:{tagline:"超解像アップスケール＋フレーム補間（ローカル / Apple Silicon）",input:"入力動画",browse:"選択…",model:"モデル",scale:"アップスケール倍率",factor:"補間倍率",cap:"解像度上限(長辺px, 0=無制限)",t_up:"アップスケール",t_interp:"フレーム補間",run:"実行",idle:"待機中",running:"処理中…",done:"完了",failed:"失敗",reveal:"フォルダで表示",nofile:"入力動画を選んでください",m_anime:"anime（線がくっきり・既定）",m_photo:"photo（実写寄り）",m_av:"anime-video（柔らかい）",ready:"準備OK（サーバ稼働中）",note:"重い処理中はログが止まって見えても、タイマーとバーが動いていれば処理中です"},
  zh:{tagline:"超分辨率放大 + 补帧（本地 / Apple Silicon）",input:"输入视频",browse:"选择…",model:"模型",scale:"放大倍率",factor:"补帧倍率",cap:"分辨率上限(长边px, 0=不限)",t_up:"放大",t_interp:"补帧",run:"运行",idle:"待机",running:"处理中…",done:"完成",failed:"失败",reveal:"在访达中显示",nofile:"请选择输入视频",m_anime:"anime（线条锐利·默认）",m_photo:"photo（写实）",m_av:"anime-video（偏柔）",ready:"就绪（服务器运行中）",note:"重负载阶段日志可能静止，但只要计时器和进度条在动，就是在处理"},
  en:{tagline:"Super-resolution upscale + frame interpolation (local / Apple Silicon)",input:"Input video",browse:"Browse…",model:"Model",scale:"Upscale ratio",factor:"Interp ratio",cap:"Max long side (px, 0=off)",t_up:"Upscale",t_interp:"Interpolate",run:"Run",idle:"Idle",running:"Working…",done:"Done",failed:"Failed",reveal:"Reveal in Finder",nofile:"Please choose an input video",m_anime:"anime (crisp lines, default)",m_photo:"photo (realistic)",m_av:"anime-video (soft)",ready:"Ready (server up)",note:"During heavy steps the log may pause — if the timer and bar are moving, it's working"}
};
let lang="ja";
function applyLang(){const d=I18N[lang];document.querySelectorAll("[data-i18n]").forEach(e=>{const k=e.getAttribute("data-i18n");if(d[k])e.textContent=d[k]});document.querySelectorAll(".lang button").forEach(b=>b.classList.toggle("on",b.dataset.lang===lang));}
document.querySelectorAll(".lang button").forEach(b=>b.onclick=()=>{lang=b.dataset.lang;applyLang();if(!baseStep)idle();});
const $=id=>document.getElementById(id);
$("pick").onclick=async()=>{const r=await fetch("/pick");const j=await r.json();if(j.path)$("path").value=j.path;};
function setBar(p){$("barfill").style.width=Math.max(0,Math.min(100,p))+"%";}
let es=null, tmr=null, spnr=null, t0=0, curStep=0, lastPct="", baseStep="";
const SPIN=["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]; let spi=0;
const RANGE={1:[0,8],2:[8,68],3:[68,90],4:[90,98],5:[98,100]};
function fmt(s){const m=Math.floor(s/60),x=s%60;return (m<10?"0":"")+m+":"+(x<10?"0":"")+x;}
function renderStep(){
  if(!baseStep)return;
  const el=fmt(Math.floor((Date.now()-t0)/1000));
  $("step").innerHTML=SPIN[spi%SPIN.length]+" "+baseStep+(lastPct?' · '+lastPct:'')+'  <span class="muted">⏱ '+el+'</span>';
}
function startTickers(){stopTickers();spnr=setInterval(()=>{spi++;renderStep();},120);tmr=setInterval(renderStep,1000);}
function stopTickers(){if(spnr)clearInterval(spnr);if(tmr)clearInterval(tmr);spnr=tmr=null;}
function idle(){stopTickers();baseStep="";$("bar").classList.remove("run");$("step").innerHTML='<span class="done">●</span> '+I18N[lang].ready+' &nbsp;<span class="muted">'+I18N[lang].note+'</span>';}
$("run").onclick=()=>{
  const inp=$("path").value.trim();
  if(!inp){alert(I18N[lang].nofile);return;}
  if(es)es.close();
  $("log").textContent="";$("result").textContent="";setBar(0);
  curStep=0;lastPct="";baseStep=I18N[lang].running;t0=Date.now();
  $("bar").classList.add("run");$("run").disabled=true;startTickers();renderStep();
  const q=new URLSearchParams({i:inp,s:$("s").value,f:$("f").value,m:$("m").value,x:$("x").value,u:$("u").checked?"on":"off",r:$("r").checked?"on":"off"});
  es=new EventSource("/run?"+q.toString());
  es.addEventListener("log",ev=>{
    const line=ev.data;
    const mStep=line.match(/\[(\d)\/5\]/);
    if(mStep){curStep=+mStep[1];lastPct="";baseStep=line.replace(/^\[\d{2}:\d{2}:\d{2}\]\s*/,"");setBar(RANGE[curStep][0]);renderStep();
      const log=$("log");log.textContent+=line+"\n";log.scrollTop=log.scrollHeight;return;}
    const mPct=line.match(/^\s*(\d+(?:\.\d+)?)%\s*$/);
    if(mPct){lastPct=Math.round(+mPct[1])+"%";renderStep();return;} // %はログに流さず「活動中」表示に使う
    const log=$("log");log.textContent+=line+"\n";log.scrollTop=log.scrollHeight;
  });
  es.addEventListener("done",ev=>{
    const j=JSON.parse(ev.data);es.close();es=null;stopTickers();$("run").disabled=false;$("bar").classList.remove("run");
    const el=fmt(Math.floor((Date.now()-t0)/1000));
    if(j.code===0){setBar(100);$("step").innerHTML='<span class="done">✓ '+I18N[lang].done+' · ⏱ '+el+'</span>';
      if(j.output){$("result").innerHTML=j.output+' &nbsp; <a href="#" id="rev">'+I18N[lang].reveal+'</a>';
        $("rev").onclick=e=>{e.preventDefault();fetch("/reveal?path="+encodeURIComponent(j.output));};}
    }else{$("step").innerHTML='<span class="bad">✗ '+I18N[lang].failed+' (exit '+j.code+')</span>';}
  });
  es.onerror=()=>{if(es){es.close();es=null;}stopTickers();$("run").disabled=false;$("bar").classList.remove("run");if(!baseStep)return;$("step").innerHTML+=' <span class="bad">(disconnected)</span>';};
};
applyLang(); idle();
</script>
</body></html>"""

# タブ用 favicon（小サイズで読みやすいようアプリアイコンを簡略化：角丸＋再生マーク）
FAVICON = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
           '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
           '<stop offset="0" stop-color="#0b3aa6"/><stop offset="1" stop-color="#38d0f8"/>'
           '</linearGradient></defs>'
           '<rect x="96" y="96" width="832" height="832" rx="210" fill="url(#g)"/>'
           '<path d="M424 356 L424 668 L688 512 Z" fill="#ffffff"/></svg>')


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _head(self, code=200, ctype="text/html; charset=utf-8"):
        self.send_response(code); self.send_header("Content-Type", ctype); self.end_headers()

    def _sse(self, event, data):
        self.wfile.write(("event: %s\n" % event).encode())
        for d in str(data).split("\n"):
            self.wfile.write(("data: %s\n" % d).encode())
        self.wfile.write(b"\n"); self.wfile.flush()

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/":
            self._head(); self.wfile.write(PAGE.encode("utf-8")); return
        if u.path == "/favicon.svg":
            self._head(200, "image/svg+xml"); self.wfile.write(FAVICON.encode("utf-8")); return
        if u.path == "/pick":
            try:
                out = subprocess.run(
                    ["osascript", "-e", 'POSIX path of (choose file with prompt "動画を選択 / Select video / 选择视频")'],
                    capture_output=True, text=True, timeout=300)
                path = out.stdout.strip()
            except Exception:
                path = ""
            self._head(200, "application/json"); self.wfile.write(json.dumps({"path": path}).encode()); return
        if u.path == "/reveal":
            p = q.get("path", [""])[0]
            if p and os.path.exists(p):
                subprocess.Popen(["open", "-R", p])
            self._head(200, "application/json"); self.wfile.write(b"{}"); return
        if u.path == "/run":
            inp = q.get("i", [""])[0]
            if not inp or not os.path.isfile(inp):
                self._head(400, "text/plain"); self.wfile.write(b"input not found"); return
            args = ["bash", SCRIPT, "-i", inp,
                    "-s", q.get("s", ["2"])[0], "-f", q.get("f", ["2"])[0],
                    "-m", q.get("m", ["anime"])[0], "-x", q.get("x", ["3840"])[0],
                    "-u", q.get("u", ["on"])[0], "-r", q.get("r", ["on"])[0]]
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            try:
                proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        bufsize=1, universal_newlines=True)
                for line in proc.stdout:
                    self._sse("log", ANSI.sub("", line.rstrip("\n")))
                proc.wait()
                out_path = os.path.splitext(inp)[0] + "_v2x.mp4"
                self._sse("done", json.dumps({"code": proc.returncode,
                                              "output": out_path if os.path.isfile(out_path) else ""}))
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception as e:
                try:
                    self._sse("log", "ERROR: " + str(e))
                    self._sse("done", json.dumps({"code": 1, "output": ""}))
                except Exception:
                    pass
            return
        self._head(404, "text/plain"); self.wfile.write(b"not found")


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


def main():
    if not os.path.isfile(SCRIPT):
        print("!! video2x.sh が見つかりません:", SCRIPT); return
    url = "http://127.0.0.1:%d/" % PORT
    try:
        httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError:
        # 既に起動中: ブラウザを開くだけで終了（アプリを何度押しても安全）
        if not os.environ.get("VIDEO2X_GUI_NOOPEN"):
            webbrowser.open(url)
        print("すでに起動中 / already running →", url)
        return
    if not os.environ.get("VIDEO2X_GUI_NOOPEN"):
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    print("video2x GUI →", url, " (Ctrl+C で終了 / Ctrl+C to stop)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
