(function(){
  'use strict';
  var CATS={'browser-only':'Browser-only','ps-host-browser-ui':'PowerShell host + browser UI','data-ai':'Data & AI','security':'Security','support':'Support repos','gpu-host':'GPU or build machine'};
  var FLAGS=[['ps51','PS 5.1','green'],['chromeEngine','Chrome/Edge','green'],['batch','.bat launcher','green'],['vbs','.vbs','yellow'],['admin','Admin','red'],['installs','Installs','red'],['network','Network','yellow'],['csharpRuntimeCompile','C# runtime compile','yellow'],['gpu','GPU','yellow'],['outlook','Outlook','yellow']];
  function el(t,c,x){var e=document.createElement(t);if(c)e.className=c;if(x!=null)e.textContent=x;return e;}
  function render(data){
    var grid=document.getElementById('grid'),q=document.getElementById('q'),cat=document.getElementById('cat'),grp=document.getElementById('grp');
    // Groups come from catalog.json ("groups", in display order; a tool's "group" is a group id). A tool with no or an unknown group lands under "Other".
    var groups=(data.groups||[]).slice(),gById={};
    if(data.tools.some(function(t){return !groups.some(function(g){return g.id===t.group;});}))groups.push({id:'',name:'Other'});
    groups.forEach(function(g){gById[g.id]=g;});
    function gOf(t){return gById[t.group]||gById[''];}
    groups.filter(function(g){return data.tools.some(function(t){return gOf(t)===g;});}).forEach(function(g){var o=el('option',null,g.name);o.value=g.id;grp.appendChild(o);});
    Object.keys(CATS).filter(function(k){return data.tools.some(function(t){return t.category===k;});}).forEach(function(k){var o=el('option',null,CATS[k]);o.value=k;cat.appendChild(o);});
    function draw(){
      var s=q.value.toLowerCase(),c=cat.value,gv=grp.value;grid.innerHTML='';
      var hits=data.tools.filter(function(t){var g=gOf(t);return(!c||t.category===c)&&(!gv||g.id===gv)&&(!s||(t.name+' '+t.summary+' '+g.name).toLowerCase().indexOf(s)>=0);});
      if(!hits.length){grid.appendChild(el('p','empty','No tools match your search.'));return;}
      groups.forEach(function(g){
        var gh=hits.filter(function(t){return gOf(t)===g;});if(!gh.length)return;
        var sec=el('section','group'),hd=el('h2','group-title',g.name);hd.id='group-'+(g.id||'other');sec.setAttribute('aria-labelledby',hd.id);sec.appendChild(hd);
        if(g.note)sec.appendChild(el('p','group-note',g.note));
        var cards=el('div','cards');sec.appendChild(cards);grid.appendChild(sec);
        gh.forEach(function(t){card(cards,t,g);});
      });
    }
    // Demo button target. It opens something that exists now; it never starts the tool and never claims the tool is running.
    // A numeric defaultPort: the tool's loopback address (where it serves once started). Otherwise the release zip, else the repo.
    function demo(t){
      if(typeof t.defaultPort==='number'){var u='http://127.0.0.1:'+t.defaultPort+'/';return{href:u,title:'Opens '+u+' in a new tab. '+t.name+' serves there once you start it'+(t.launcher?' with '+t.launcher:'')+'; this button does not start it.'+(t.portNote?' '+t.portNote:'')};}
      if(t.releases)return{href:t.releases,title:'Opens the latest '+t.name+' release (zip) on GitHub in a new tab.'};
      if(t.repo)return{href:t.repo,title:'Opens the '+t.name+' repository on GitHub in a new tab.'};
      return null;
    }
    function card(grid,t,g){
      {
        var d=el('article','card box');d.appendChild(el('span','cat',CATS[t.category]||t.category));var h=el('h3'),ha=el('a',null,t.name);ha.href='tools/'+t.id+'.html';var em=el('img','emblem');em.src='assets/emblems/'+t.id+'.svg';em.alt='';em.setAttribute('aria-hidden','true');em.width=32;em.height=32;em.onerror=function(){this.remove();};h.appendChild(em);h.appendChild(ha);d.appendChild(h);d.appendChild(el('p',null,t.summary));
        var b=el('div','badges');FLAGS.forEach(function(f){if(t.requirements[f[0]])b.appendChild(el('span','badge '+f[2],f[1]));});
        if(!t.requirements.admin)b.appendChild(el('span','badge green','No admin'));
        var au=t.automation;if(au){if(au.cli)b.appendChild(el('span','badge green','CLI'));if(au.json)b.appendChild(el('span','badge green','JSON output'));if(au.api)b.appendChild(el('span','badge green',au.api==='openai-v1'?'OpenAI API':'API'));if(au.mcp)b.appendChild(el('span','badge green','MCP'));}   // CONVENTIONS.md: CLI and API for agents
        if(t.defaultPort==='auto')b.appendChild(el('span','badge grey','free port'));else if(typeof t.defaultPort==='number')b.appendChild(el('span','badge grey','port '+t.defaultPort));
        b.appendChild(el('span','badge grey',t.status));if(g.support)b.appendChild(el('span','badge grey','Support repo, not a user tool'));d.appendChild(b);
        var note=t.requirements.installs?(t.installNote||'Needs third-party installs; see the repo README.'):t.launcher?'':'Nothing to launch yet.';
        if(note)d.appendChild(el('p',null,note));if(t.external&&t.externalSource)d.appendChild(el('p',null,'Source: '+t.externalSource));
        var l=el('div','links'),dm=g.support?null:demo(t);
        if(dm){var btn=el('a','btn demo','Demo');btn.href=dm.href;btn.title=dm.title;btn.target='_blank';btn.rel='noopener';l.appendChild(btn);}
        if(t.repo){var a=el('a',null,'Repository');a.href=t.repo;l.appendChild(a);}
        if(t.releases){var r=el('a',null,'Latest release (zip)');r.href=t.releases;l.appendChild(r);}
        d.appendChild(l);grid.appendChild(d);
      }
    }
    q.addEventListener('input',draw);cat.addEventListener('change',draw);grp.addEventListener('change',draw);draw();
  }
  var fallback=function(){render(window.EDGE_OPS_CATALOG);};
  if(location.protocol==='file:'||!window.fetch){fallback();return;}
  fetch('catalog.json',{cache:'no-cache'}).then(function(r){if(!r.ok)throw 0;return r.json();}).then(render,fallback);
})();
