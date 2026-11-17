// Player documents share the slide_preview library and its localisation.
part of '../slide_preview.dart';

// No tracking-origin API script: speak the iframe's widget protocol directly.
// Subscribe after its handshake; iframe load/readiness is not playback proof.
String _youTubeHtml(
  String embedUrl,
  int startMs,
  int endMs, {
  required int generation,
  required bool autoplay,
  required String playLabel,
  required String waitingLabel,
}) {
  String literal(String value) => jsonEncode(value).replaceAll('<', r'\u003c');
  return '''<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;background:#000;height:100%}iframe{width:100%;height:100%;border:0}
#recovery{position:absolute;inset:0;display:none;align-items:center;justify-content:center;background:#0009;color:white;font:18px sans-serif;text-align:center}
button{font:inherit;padding:12px 24px;cursor:pointer}</style></head>
<body><iframe id="f" src="$embedUrl" allow="autoplay; fullscreen; encrypted-media; picture-in-picture" allowfullscreen></iframe>
<div id="recovery" role="status"><div><p id="reason"></p><button id="play" type="button"></button></div></div>
<script>
var generation=$generation;
var startMs=$startMs, endMs=$endMs, autoplay=$autoplay, ready=false, ended=false;
var playing=false, hasPlayed=false, subscribed=false, lastPosition=null, lastCorrection=null;
var f=document.getElementById('f'), recovery=document.getElementById('recovery');
document.getElementById('play').textContent=${literal(playLabel)};
document.getElementById('reason').textContent=${literal(waitingLabel)};
function post(m){try{OciDeck.postMessage(generation+'|'+m)}catch(e){}}
function send(o){o.id=1;o.channel='widget';try{f.contentWindow.postMessage(JSON.stringify(o),'$kYouTubeEmbedOrigin')}catch(e){}}
function command(name,args){send({event:'command',func:name,args:args||[]})}
function listen(){send({event:'listening'})}
function subscribe(){if(subscribed)return;subscribed=true;
  ['onReady','onStateChange','onError','onAutoplayBlocked'].forEach(function(name){command('addEventListener',[name])});
}
function markReady(){if(!ready){ready=true;post('ok')}}
function markPlaying(){markReady();hasPlayed=true;recovery.style.display='none';if(!playing){playing=true;post('playback:playing')}}
function recover(state){if(!autoplay||hasPlayed)return;recovery.style.display='flex';post('playback:'+state)}
function finish(){if(!ended){ended=true;post('ended')}}
function state(value){
  if(value===1)markPlaying();
  else if(value===0){playing=false;finish()}
  else if(value===2||value===5){if(playing)post('playback:paused');playing=false}
}
function position(ms){
  // Bound every new overshoot, including seeks after the first ended event.
  var target=ms<startMs?startMs:(endMs>0&&ms>=endMs?endMs:null);
  if(target!==null){
    if(lastCorrection!==ms){
      if(endMs>0&&ms>=endMs)command('pauseVideo');
      command('seekTo',[target/1000,true]);lastCorrection=ms;
    }
    if(endMs>0&&ms>=endMs)finish();
    post('pos:'+target);return;
  }
  lastCorrection=null;
  if(playing&&lastPosition!==null&&ms>lastPosition)ended=false;
  lastPosition=ms;post('pos:'+ms);
}
document.getElementById('play').addEventListener('click',function(){
  // Keep the play command inside this real user activation; no reload/mute.
  if(ended){command('seekTo',[startMs/1000,true]);ended=false;lastPosition=null}
  playing=false;command('playVideo');
});
var tries=0,poke=setInterval(function(){listen();if(++tries>40||ready)clearInterval(poke)},250);
f.addEventListener('load',function(){listen()});
window.addEventListener('message',function(e){
  if(e.origin!=='$kYouTubeEmbedOrigin'||e.source!==f.contentWindow)return;
  var d;try{d=(typeof e.data==='string')?JSON.parse(e.data):e.data}catch(x){return}
  if(!d||!d.event)return;
  if(d.event==='readyToListen'){listen();return}
  subscribe();
  if(d.event==='onReady'||d.event==='initialDelivery')markReady();
  if(d.event==='onAutoplayBlocked'){playing=false;recover('blocked')}
  else if(d.event==='onError'){recovery.style.display='none';post('err:'+d.info)}
  else if(d.event==='onStateChange'){
    state(d.info);
  } else if((d.event==='infoDelivery'||d.event==='initialDelivery')&&d.info){
    markReady();
    state(d.info.playerState);
    if(typeof d.info.currentTime==='number')position(Math.round(d.info.currentTime*1000));
  }
});
if(autoplay){post('playback:requested');setTimeout(function(){recover('waiting')},6000)}
setTimeout(function(){if(!ready)post('err:noapi')},8000);
</script></body></html>''';
}

/// HTML voor een Vimeo-embed via player.js. Start gaat via de #t-fragment in
/// [embedUrl]; het knip-einde ([endMs] > 0) wordt in JS bewaakt.
String _vimeoHtml(String embedUrl, int startMs, int endMs, int generation) {
  return '''<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;background:#000;height:100%}iframe{width:100%;height:100%;border:0}</style></head>
<body><iframe id="f" src="$embedUrl" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>
<script src="https://player.vimeo.com/api/player.js"></script>
<script>
var generation=$generation;
var startMs=$startMs,endMs=$endMs,ready=false,ended=false,lastCorrection=null;
function post(m){try{OciDeck.postMessage(generation+'|'+m)}catch(e){}}
function finish(){if(!ended){ended=true;post('ended')}}
if(window.Vimeo){
  var player=new Vimeo.Player(document.getElementById('f'));
  player.on('timeupdate',function(d){
    ready=true;var ms=Math.round(d.seconds*1000);
    var target=ms<startMs?startMs:(endMs>0&&ms>=endMs?endMs:null);
    if(target!==null){
      if(lastCorrection!==ms){
        if(endMs>0&&ms>=endMs)player.pause().catch(function(){});
        player.setCurrentTime(target/1000).catch(function(){});lastCorrection=ms;
      }
      if(endMs>0&&ms>=endMs)finish();post('pos:'+target);return;
    }
    lastCorrection=null;post('pos:'+ms);
  });
  player.on('play',function(){if(ended){ended=false;player.setCurrentTime(startMs/1000).catch(function(){})}});
  player.on('loaded',function(){ready=true;post('ok')});
  player.on('ended',finish);
  player.on('error',function(e){post('err:'+((e&&e.name)||'vimeo'))});
} else { post('err:noapi'); }
setTimeout(function(){if(!ready){post('err:noapi')}},8000);
</script></body></html>''';
}

/// Exact origins for this active player and its private loopback document.
/// A shared browser profile must never turn this into a grant for other views.
@visibleForTesting
bool videoEmbedAutoplayPermissionAllowed({
  required int kind,
  required String url,
  required Uri? player,
  required Uri? document,
  required bool active,
  required bool allowRemoteMedia,
  required bool autoplay,
}) {
  if (kind != WinWebViewPermissionResourceType.autoplay.nativeId ||
      !active ||
      !allowRemoteMedia ||
      !autoplay) {
    return false;
  }
  final request = Uri.tryParse(url);
  if (request == null || request.userInfo.isNotEmpty) return false;
  bool sameOrigin(Uri? expected) =>
      expected != null &&
      request.scheme == expected.scheme &&
      request.host == expected.host &&
      request.port == expected.port;
  return sameOrigin(player) || sameOrigin(document);
}
