(function(){
  'use strict';
  var CATS={'browser-only':'Browser-only','ps-host-browser-ui':'PowerShell host + browser UI','data-ai':'Data & AI','security':'Security'};
  var FLAGS=[['ps51','PS 5.1','green'],['chromeEngine','Chrome/Edge','green'],['batch','.bat launcher','green'],['vbs','.vbs','yellow'],['admin','Admin','red'],['installs','Installs','red'],['network','Network','yellow'],['csharpRuntimeCompile','C# runtime compile','yellow'],['gpu','GPU','yellow'],['outlook','Outlook','yellow']];
  function el(t,c,x){var e=document.createElement(t);if(c)e.className=c;if(x!=null)e.textContent=x;return e;}
  function render(data){
    var grid=document.getElementById('grid'),q=document.getElementById('q'),cat=document.getElementById('cat');
    Object.keys(CATS).forEach(function(k){var o=el('option',null,CATS[k]);o.value=k;cat.appendChild(o);});
    function draw(){
      var s=q.value.toLowerCase(),c=cat.value;grid.innerHTML='';
      var hits=data.tools.filter(function(t){return(!c||t.category===c)&&(!s||(t.name+' '+t.summary).toLowerCase().indexOf(s)>=0);});
      if(!hits.length){grid.appendChild(el('p','empty','No tools match your search.'));return;}
      hits.forEach(function(t){
        var d=el('article','card box');d.appendChild(el('span','cat',CATS[t.category]||t.category));var h=el('h2'),ha=el('a',null,t.name);ha.href='tools/'+t.id+'.html';h.appendChild(ha);d.appendChild(h);d.appendChild(el('p',null,t.summary));
        var b=el('div','badges');FLAGS.forEach(function(f){if(t.requirements[f[0]])b.appendChild(el('span','badge '+f[2],f[1]));});
        if(!t.requirements.admin)b.appendChild(el('span','badge green','No admin'));
        if(t.defaultPort)b.appendChild(el('span','badge grey','port '+t.defaultPort));
        b.appendChild(el('span','badge grey',t.status));d.appendChild(b);
        d.appendChild(el('p',null,'Launch: '+t.launcher+(t.external?' — source: '+t.externalSource:'')));
        var l=el('div','links'),a=el('a',null,'Repository');a.href=t.repo;l.appendChild(a);
        if(t.releases){var r=el('a',null,'Latest release (zip)');r.href=t.releases;l.appendChild(r);}
        d.appendChild(l);grid.appendChild(d);
      });
    }
    q.addEventListener('input',draw);cat.addEventListener('change',draw);draw();
  }
  var fallback=function(){render(window.EDGE_OPS_CATALOG);};
  if(location.protocol==='file:'||!window.fetch){fallback();return;}
  fetch('catalog.json',{cache:'no-cache'}).then(function(r){if(!r.ok)throw 0;return r.json();}).then(render,fallback);
})();
