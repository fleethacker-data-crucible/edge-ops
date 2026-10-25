/*! FleetHacker UI Kit v0.1.0 | vanilla, no deps, classic script (works from file://) */
(function(){'use strict';
var FH=window.FH={version:'0.1.0'};var KEY='fh-theme';
function $$(s,r){return Array.prototype.slice.call((r||document).querySelectorAll(s));}
/* Theme toggle: <button data-fh-theme-toggle> */
FH.setTheme=function(t){var d=document.documentElement;if(t)d.setAttribute('data-theme',t);else d.removeAttribute('data-theme');try{t?localStorage.setItem(KEY,t):localStorage.removeItem(KEY);}catch(e){}
 $$('[data-fh-theme-toggle]').forEach(function(b){var dark=FH.currentTheme()==='dark';b.setAttribute('aria-pressed',String(dark));});};
FH.currentTheme=function(){var a=document.documentElement.getAttribute('data-theme');if(a)return a;return matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';};
try{var saved=localStorage.getItem(KEY);if(saved)document.documentElement.setAttribute('data-theme',saved);}catch(e){}
function initTheme(){$$('[data-fh-theme-toggle]').forEach(function(b){b.setAttribute('aria-pressed',String(FH.currentTheme()==='dark'));
 b.addEventListener('click',function(){FH.setTheme(FH.currentTheme()==='dark'?'light':'dark');FH.toast('Theme: '+FH.currentTheme());});});}
/* Dialog: <button data-fh-dialog-open="id">, native <dialog class="fh-dialog" aria-labelledby>; [data-fh-dialog-close] */
function initDialogs(){$$('[data-fh-dialog-open]').forEach(function(b){b.addEventListener('click',function(){var d=document.getElementById(b.getAttribute('data-fh-dialog-open'));if(!d)return;d._opener=b;d.showModal();var f=d.querySelector('[autofocus],button,input,select,textarea,a[href]');if(f)f.focus();});});
 $$('dialog.fh-dialog').forEach(function(d){d.addEventListener('close',function(){if(d._opener)d._opener.focus();});
  d.addEventListener('click',function(e){if(e.target===d)d.close('cancel');});
  $$('[data-fh-dialog-close]',d).forEach(function(c){c.addEventListener('click',function(){d.close(c.value||'');});});});}
/* Tabs: .fh-tabs > [role=tablist] > [role=tab][aria-controls]; arrow/Home/End, automatic activation */
function initTabs(){$$('.fh-tabs').forEach(function(w){var tabs=$$('[role=tab]',w);
 function sel(t,focus){tabs.forEach(function(x){var on=x===t;x.setAttribute('aria-selected',String(on));x.tabIndex=on?0:-1;var p=document.getElementById(x.getAttribute('aria-controls'));if(p)p.hidden=!on;});if(focus)t.focus();}
 tabs.forEach(function(t,i){t.addEventListener('click',function(){sel(t);});t.addEventListener('keydown',function(e){var n=null;
  if(e.key==='ArrowRight')n=tabs[(i+1)%tabs.length];else if(e.key==='ArrowLeft')n=tabs[(i-1+tabs.length)%tabs.length];else if(e.key==='Home')n=tabs[0];else if(e.key==='End')n=tabs[tabs.length-1];
  if(n){e.preventDefault();sel(n,true);}});});
 sel(tabs.filter(function(t){return t.getAttribute('aria-selected')==='true';})[0]||tabs[0]);});}
/* Disclosure: <button class="fh-disclosure__btn" aria-expanded="false" aria-controls="id"> */
function initDisclosure(){$$('.fh-disclosure__btn[aria-controls]').forEach(function(b){var p=document.getElementById(b.getAttribute('aria-controls'));if(!p)return;p.hidden=b.getAttribute('aria-expanded')!=='true';
 b.addEventListener('click',function(){var o=b.getAttribute('aria-expanded')==='true';b.setAttribute('aria-expanded',String(!o));p.hidden=o;});});}
/* Toast: FH.toast(msg,{type:'ok'|'bad'|'info',timeout:ms}) -> polite live region (assertive for 'bad') */
var region,alertRegion;function ensure(){if(region)return;var c=document.createElement('div');c.className='fh-toasts';
 region=document.createElement('div');region.setAttribute('role','status');region.setAttribute('aria-live','polite');
 alertRegion=document.createElement('div');alertRegion.setAttribute('role','alert');
 c.appendChild(region);c.appendChild(alertRegion);region.style.display=alertRegion.style.display='contents';document.body.appendChild(c);}
FH.toast=function(msg,o){o=o||{};ensure();var t=document.createElement('div');t.className='fh-toast fh-toast--'+(o.type||'info');
 var s=document.createElement('span');s.textContent=msg;var x=document.createElement('button');x.type='button';x.setAttribute('aria-label','Dismiss notification');x.textContent='\u00d7';
 x.addEventListener('click',function(){t.remove();});t.appendChild(s);t.appendChild(x);(o.type==='bad'?alertRegion:region).appendChild(t);
 var ms=o.timeout===0?0:(o.timeout||6000);if(ms){var h=setTimeout(function(){t.remove();},ms);t.addEventListener('mouseenter',function(){clearTimeout(h);});t.addEventListener('focusin',function(){clearTimeout(h);});}return t;};
FH.init=function(){initTheme();initDialogs();initTabs();initDisclosure();$$('[data-fh-toast]').forEach(function(b){b.addEventListener('click',function(){FH.toast(b.getAttribute('data-fh-toast'),{type:b.getAttribute('data-fh-toast-type')||'info'});});});};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',FH.init);else FH.init();
})();
