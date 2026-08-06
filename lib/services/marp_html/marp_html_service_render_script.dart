// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// Het script dat in het geopende document de ingesloten markdown omzet: marked,
// DOMPurify, highlight.js, mermaid, MathJax, en het terugzetten van de
// ingesloten afbeeldingen. Uitgetild uit de hoofdbibliotheek voor de
// bestandsgrootte-ratchet.
part of '../marp_html_service.dart';

/// De labels die het renderscript in het document zet, als JSON. Het script
/// is vaste, vendorloze code; alleen deze woorden zijn zichtbare tekst en gaan
/// dus door [AppLocalizations.d]. Een `</script` in een vertaling wordt door
/// [_guardScript] afgevangen, net als bij de bibliotheken.
String _renderScriptLabels() {
  const l10n = AppLocalizations(Locale('nl'));
  return jsonEncode({
    'mermaidFailed': l10n.d('Dit diagram kon niet worden getekend'),
    'mermaidSource': l10n.d('Brontekst van het diagram'),
  });
}

/// Het script dat de ingesloten markdown in het geopende document omzet.
///
/// Een functie en geen constante, omdat de zichtbare woorden erin
/// gelokaliseerd worden (zie [_renderScriptLabels]) en omdat de ingesloten
/// afbeeldingen als [dataUris] meegaan — één keer, hoe vaak een dia er ook
/// naar verwijst.
String _renderScript(List<String> dataUris) =>
    'var OCIDECK_L=${_renderScriptLabels()};\n'
    'var OCIDECK_IMG=${jsonEncode(dataUris)};\n'
    '$_renderScriptBody';

const _renderScriptBody = r'''
(function(){
// Defence-in-depth: mermaid injects its SVG into the DOM AFTER DOMPurify has
// run on the markdown, so sanitise the produced SVG ourselves too (mirrors
// the in-app sanitize_svg.dart). Mermaid also runs with securityLevel strict.
function sanitizeMermaid(){
  if(!window.DOMPurify)return;
  document.querySelectorAll('.mermaid svg').forEach(function(svg){
    try{
      var clean=DOMPurify.sanitize(svg.outerHTML,{USE_PROFILES:{svg:true,svgFilters:true}});
      var tpl=document.createElement('template');tpl.innerHTML=clean;
      var node=tpl.content.firstElementChild;
      if(node)svg.replaceWith(node);
    }catch(e){}
  });
}
if(window.marked&&marked.setOptions){marked.setOptions({gfm:true,breaks:false});}
// section.slide (dia-modus) én section.document (doorlopende documentmodus):
// beide dragen hun body als inerte markdown-payload en worden hier client-side
// door marked+DOMPurify gerenderd — de enige renderroute.
document.querySelectorAll('section.slide,section.document').forEach(function(sec){
  var holder=sec.querySelector('script[type="text/markdown"]');
  var src=holder?holder.textContent:'';
  // De ontsnapping uit _guardMarkdown terugdraaien: die bestaat alleen om de
  // HTML-tokenizer binnen dit script-element te houden, niet om de markdown
  // te veranderen.
  src=src.split('<\\/').join('</').split('<\\!--').join('<!--');
  var div=document.createElement('div');div.className='content';
  var html=window.marked?marked.parse(src):src;
  // Sanitise rendered Markdown before it touches the DOM: a deck must not be
  // able to run script/onerror/javascript: payloads when the export is opened.
  // If the sanitiser somehow isn't present, fail closed to plain text.
  if(window.DOMPurify){div.innerHTML=DOMPurify.sanitize(html);}else{div.textContent=src;}
  sec.innerHTML='';sec.appendChild(div);
});
// De ingesloten afbeeldingen terugzetten. Ze staan één keer in OCIDECK_IMG en
// de dia's dragen alleen een verwijzing, zodat dezelfde achtergrond op veertig
// dia's het bestand niet veertig keer zo groot maakt. Alleen een echte
// data:image/-waarde uit onze eigen lijst wordt gezet — de index komt uit het
// document en moet dus als onbetrouwbaar worden behandeld.
document.querySelectorAll('img[src^="#ocideck-img-"]').forEach(function(el){
  var n=parseInt(el.getAttribute('src').replace('#ocideck-img-',''),10);
  var uri=OCIDECK_IMG[n];
  if(typeof uri==='string'&&uri.indexOf('data:image/')===0){el.setAttribute('src',uri);}
  else{el.removeAttribute('src');}
});
document.querySelectorAll('code.language-mermaid').forEach(function(code){
  var pre=code.closest('pre');if(!pre)return;
  var holder=document.createElement('pre');holder.className='mermaid';
  holder.textContent=code.textContent;pre.replaceWith(holder);
});
if(window.hljs){document.querySelectorAll('pre code').forEach(function(el){try{hljs.highlightElement(el);}catch(e){}});}
// Een diagram dat mermaid niet kan lezen wordt een leesbare melding IN het
// document. De ontvanger van een export heeft geen console: zonder dit zag hij
// mermaids eigen Engelse bom-plaatje ("Syntax error in text") zonder enige
// aanwijzing wélk diagram het betrof of wat eraan mankeerde, en de auteur zag
// helemaal niets. Alles gaat via textContent, dus de brontekst van het
// diagram kan hier nooit opmaak of markup worden.
function mermaidNotice(pre,err){
  var box=document.createElement('div');box.className='mermaid-error';
  var title=document.createElement('p');
  title.className='mermaid-error-title';
  title.textContent=OCIDECK_L.mermaidFailed;
  box.appendChild(title);
  var detail=err&&err.message?String(err.message):'';
  if(detail){
    var d=document.createElement('pre');
    d.className='mermaid-error-detail';d.textContent=detail;
    box.appendChild(d);
  }
  var label=document.createElement('p');
  label.className='mermaid-error-label';
  label.textContent=OCIDECK_L.mermaidSource;
  var src=document.createElement('pre');
  src.className='mermaid-error-source';src.textContent=pre.textContent;
  box.appendChild(label);box.appendChild(src);
  pre.replaceWith(box);
}
function noticeForUnrendered(err){
  document.querySelectorAll('pre.mermaid').forEach(function(pre){
    if(!pre.querySelector('svg'))mermaidNotice(pre,err);
  });
}
function runMermaid(){
  // htmlLabels UIT, per diagramsoort én globaal. Mermaid tekent labels
  // anders in een <foreignObject> met HTML erin, en juist dat element haalt
  // de sanitisatie hieronder weg (het is de plek waar HTML een SVG binnen kan
  // komen). Het resultaat waren lege vakjes en pijlen zonder één woord erbij
  // — een diagram dat er wél stond maar niets meer zei.
  mermaid.initialize({startOnLoad:false,securityLevel:'strict',
    htmlLabels:false,flowchart:{htmlLabels:false},class:{htmlLabels:false}});
  // Elk diagram eerst apart laten controleren. Zo tekent mermaid zijn eigen
  // foutplaatje niet, blijft een kapot diagram beperkt tot zijn eigen dia, en
  // draait de sanitisatie hieronder ALTIJD — bij de oude stille catch sloeg
  // die voor het hele document over zodra er één diagram omviel, ook voor de
  // diagrammen die het wél deden.
  var checked=[];
  document.querySelectorAll('pre.mermaid').forEach(function(pre){
    checked.push(Promise.resolve()
      .then(function(){return mermaid.parse(pre.textContent);})
      .catch(function(e){mermaidNotice(pre,e);}));
  });
  return Promise.all(checked)
    .then(function(){return mermaid.run();})
    .catch(noticeForUnrendered)
    .then(sanitizeMermaid);
}
if(window.mermaid){try{runMermaid();}catch(e){noticeForUnrendered(e);}}
if(window.MathJax&&MathJax.typesetPromise){MathJax.typesetPromise();}
})();
''';
