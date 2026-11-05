(function(){
  'use strict';
  var CATS={'browser-only':'Browser-only','ps-host-browser-ui':'PowerShell host + browser UI','data-ai':'Data & AI','security':'Security','support':'Support repos','gpu-host':'GPU or build machine'};
  var FLAGS=[['ps51','PS 5.1','green'],['chromeEngine','Chrome/Edge','green'],['batch','.bat launcher','green'],['vbs','.vbs','yellow'],['admin','Admin','red'],['installs','Installs','red'],['network','Network','yellow'],['csharpRuntimeCompile','C# runtime compile','yellow'],['gpu','GPU','yellow'],['outlook','Outlook','yellow']];
  function el(t,c,x){var e=document.createElement(t);if(c)e.className=c;if(x!=null)e.textContent=x;return e;}
  function render(data){
    window.EDGE_OPS_CATALOG=data;
    var grid=document.getElementById('grid'),q=document.getElementById('q'),cat=document.getElementById('cat'),grp=document.getElementById('grp');
    // Group order is the order in catalog.json. The first four are the primary rows; voice, secrets and support follow and stay visible.
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
    function safeHttps(url){return(typeof url==='string'&&/^https:\/\/\S+$/.test(url))?url:'';}
    function isPages(u){return /\.github\.io\//i.test(u);}
    function isRaw(u){return /raw\.githubusercontent\.com/i.test(u);}
    // A Commissioning Pages URL wins over a raw.githubusercontent mp4. demoVideo is checked first, then demoPage.
    function pickDemo(dv,dp){
      if(dv&&isPages(dv))return dv;
      if(dp&&isPages(dp))return dp;
      if(dv&&!isRaw(dv))return dv;
      if(dp&&!isRaw(dp))return dp;
      return dv||dp||'';
    }
    // Demo opens a new tab and never starts the tool. file:// is the workstation, so a numeric defaultPort wins.
    // Hosted Pages prefer the commissioning video or page, because 127.0.0.1 there is not the visitor's computer.
    // The files stay in fleethacker-data-crucible/Commissioning; this repo stores the https URL only.
    function demo(t){
      var port=null,video=null;
      if(typeof t.defaultPort==='number'){var u='http://127.0.0.1:'+t.defaultPort+'/';port={href:u,title:'Opens '+u+' in a new tab. '+t.name+' serves there once you start it'+(t.launcher?' with '+t.launcher:'')+'; this button does not start it.'+(t.portNote?' '+t.portNote:'')};}
      var dv=safeHttps(t.demoVideo),dp=safeHttps(t.demoPage),chosen=pickDemo(dv,dp);
      if(chosen){
        var asPage=chosen===dp&&chosen!==dv;
        video={href:chosen,title:asPage?('Opens the '+t.name+' commissioning page in a new tab. This button does not start it.'):('Opens the '+t.name+' commissioning video in a new tab. The video stays in the Commissioning repository; this button does not start it.')};
      }
      var file=location.protocol==='file:';
      if(file&&port)return port;if(video)return video;if(port)return port;
      if(t.releases)return{href:t.releases,title:'Opens the latest '+t.name+' release (zip) on GitHub in a new tab.'};
      if(t.repo)return{href:t.repo,title:'Opens the '+t.name+' repository on GitHub in a new tab.'};
      return null;
    }
    function batName(launcher){
      var s=String(launcher||'').trim().split(/\s+/)[0]||'';
      if(s.indexOf('/')>=0||s.indexOf('\\')>=0)return '';
      return /^[A-Za-z0-9_.-]+\.bat$/i.test(s)?s:'';
    }
    function canLaunch(t,g){return !!(periscopeLocal&&!(g&&g.support)&&batName(t.launcher));}
    function periscopeToken(){var meta=document.querySelector('meta[name="periscope-token"]');return meta?meta.getAttribute('content'):'';}
    function api(path,opt){
      var headers={Accept:'application/json'},token=periscopeToken();
      if(token)headers.Authorization='Bearer '+token;
      if(opt&&opt.body)headers['Content-Type']='application/json';
      var url=new URL(path,document.baseURI).href;
      return fetch(url,{method:(opt&&opt.method)||'GET',headers:headers,body:opt&&opt.body,cache:'no-store'}).then(function(r){
        return r.json().then(function(j){return {status:r.status,body:j};},function(){return {status:r.status,body:null};});
      });
    }
    function callout(card,text){
      var box=card.querySelector('.periscope-callout');
      if(!box){box=el('div','periscope-callout');box.setAttribute('role','status');card.appendChild(box);}
      box.textContent=text;
    }
    function beginLaunch(t,button,statusEl,card){
      button.disabled=true;button.textContent='Checking\u2026';statusEl.textContent='Checking';
      api('api/periscope/launch',{method:'POST',body:JSON.stringify({tool:t.id})}).then(function(res){
        var body=res.body||{},result=body.result||{};
        if(!body.ok){button.disabled=false;button.textContent='Launch';statusEl.textContent=(body.error&&body.error.code?body.error.code+': ':'')+(body.error&&body.error.message||'Launch failed');return;}
        if(result.state==='walkthrough'){button.disabled=false;button.textContent='Launch';callout(card,result.message||'');statusEl.textContent='Gangplank setup';return;}
        if(result.state==='launched'){button.disabled=false;button.textContent='Launch';statusEl.textContent='Launched';return;}
        if(!result.job){button.disabled=false;button.textContent='Launch';statusEl.textContent='Launch failed';return;}
        pollLaunch(result.job,button,statusEl,card,0);
      },function(){button.disabled=false;button.textContent='Launch';statusEl.textContent='Launch failed';});
    }
    function pollLaunch(job,button,statusEl,card,n){
      if(n>600){button.disabled=false;button.textContent='Launch';statusEl.textContent='GANGPLANK_TIMEOUT: Gangplank did not respond in time.';return;}
      api('api/periscope/download-status?job='+encodeURIComponent(job)).then(function(res){
        var body=res.body||{},result=body.result||{};
        if(!body.ok){button.disabled=false;button.textContent='Launch';statusEl.textContent=(body.error&&body.error.code?body.error.code+': ':'')+(body.error&&body.error.message||'Launch failed');return;}
        if(result.step){button.textContent=result.step;statusEl.textContent=result.step;}
        if(result.state==='launched'){button.disabled=false;button.textContent='Launch';statusEl.textContent='Launched';return;}
        if(result.state==='walkthrough'){button.disabled=false;button.textContent='Launch';callout(card,result.message||'');statusEl.textContent='Gangplank setup';return;}
        if(result.state==='error'||result.ok===false){button.disabled=false;button.textContent='Launch';statusEl.textContent=(result.code?result.code+': ':'')+(result.message||'Launch failed');return;}
        setTimeout(function(){pollLaunch(job,button,statusEl,card,n+1);},500);
      },function(){button.disabled=false;button.textContent='Launch';statusEl.textContent='Launch failed';});
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
        if(canLaunch(t,g)){var lb=el('button','btn launch','Launch');lb.type='button';lb.setAttribute('aria-label','Launch '+t.name);var ls=el('span','launch-status','');ls.setAttribute('role','status');lb.addEventListener('click',function(){beginLaunch(t,lb,ls,d);});l.appendChild(lb);l.appendChild(ls);}
        if(t.repo){var a=el('a',null,'Repository');a.href=t.repo;l.appendChild(a);}
        if(t.releases){var r=el('a',null,'Latest release (zip)');r.href=t.releases;l.appendChild(r);}
        d.appendChild(l);grid.appendChild(d);
      }
    }
    if(!q.getAttribute('data-wired')){q.setAttribute('data-wired','');q.addEventListener('input',draw);cat.addEventListener('change',draw);grp.addEventListener('change',draw);}
    window.EDGE_OPS_REDRAW=draw;draw();
  }
  var periscopeLocal=false;
  function probePeriscope(){
    if(!window.fetch)return Promise.resolve(false);
    var meta=document.querySelector('meta[name="periscope-token"]'),token=meta?meta.getAttribute('content'):'';
    var headers={Accept:'application/json'};
    if(token)headers.Authorization='Bearer '+token;
    var url;try{url=new URL('api/periscope/status',document.baseURI).href;}catch(e){return Promise.resolve(false);}
    return fetch(url,{headers:headers,cache:'no-store'}).then(function(r){if(!r.ok)throw 0;return r.json();}).then(function(body){
      return !!(body&&body.ok===true&&body.v===1&&body.result&&body.result.local===true);
    },function(){return false;});
  }
  function boot(data){
    render(data);
    probePeriscope().then(function(ok){periscopeLocal=!!ok;if(ok&&window.EDGE_OPS_REDRAW)window.EDGE_OPS_REDRAW();});
  }
  var fallback=function(){boot(window.EDGE_OPS_CATALOG);};
  if(location.protocol==='file:'||!window.fetch){fallback();return;}
  fetch('catalog.json',{cache:'no-cache'}).then(function(r){if(!r.ok)throw 0;return r.json();}).then(boot,fallback);
})();
