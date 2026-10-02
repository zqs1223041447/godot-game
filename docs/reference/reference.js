'use strict';
(() => {
const data=JSON.parse(document.getElementById('reference-data').textContent);
const query=document.getElementById('query'),facet=document.getElementById('facet'),status=document.getElementById('status');
const records=data.records,byId=Object.fromEntries(records.map(r=>[r.id,r]));
let category='skills',treeOnly=false,selectedNode='',zoom=1;
function refreshFacets(){const values=[...new Set(records.filter(r=>category==='all'||r.cat===category).map(r=>r.facet).filter(Boolean))].sort();facet.replaceChildren(new Option('全部',''),...values.map(v=>new Option(v,v)));}
function filter(){const term=query.value.trim().toLocaleLowerCase(),searching=term.length>0;let count=0;
for(const r of records){const show=(searching||category==='all'||r.cat===category)&&(!term||r.search.includes(term))&&(!facet.value||r.facet===facet.value)&&(!status.value||r.status===status.value)&&!treeOnly;document.getElementById(r.id).hidden=!show;if(show)count++;}
document.getElementById('tree').hidden=!(treeOnly||(category==='passives'&&!searching));
document.getElementById('result-count').textContent=treeOnly?'可浏览全部珠宝孔':`${count} 条${searching?' · 跨目录搜索':''}`;
document.getElementById('empty').hidden=count>0||treeOnly;
document.getElementById('category-title').textContent=treeOnly?'天赋与寻枝覆盖':(searching?'搜索结果':(data.categories[category]||'全部条目'));
for(const a of document.querySelectorAll('.nav-link'))a.classList.toggle('active',a.dataset.category===category&&!treeOnly);
}
function navigate(){const hash=decodeURIComponent(location.hash.slice(1));const entry=byId[hash];
if(entry){category=entry.cat;treeOnly=false;query.value='';status.value='';refreshFacets();filter();requestAnimationFrame(()=>{const el=document.getElementById(hash);el.scrollIntoView({block:'start'});el.focus({preventScroll:true});});}
else if(hash==='tree'){treeOnly=true;query.value='';filter();requestAnimationFrame(()=>document.getElementById('tree').scrollIntoView({block:'start'}));}
else if(hash.startsWith('category-')||!hash){category=hash.slice(9)||'skills';if(category!=='all'&&!data.categories[category])category='skills';treeOnly=false;query.value='';status.value='';refreshFacets();filter();window.scrollTo(0,0);}
}
query.addEventListener('input',()=>{treeOnly=false;facet.value='';filter();});facet.addEventListener('change',filter);status.addEventListener('change',filter);
document.getElementById('clear-search').addEventListener('click',()=>{query.value='';facet.value='';status.value='';filter();query.focus();});
window.addEventListener('hashchange',navigate);
const choice=document.getElementById('socket-choice'),mode=document.getElementById('tree-mode'),svg=document.getElementById('passive-map');
function renderTree(){const sample=data.coverage[choice.value];if(!sample)return;const analysis=sample[mode.value],source=analysis.active_sources[choice.value],disc=document.getElementById('coverage-radius');
disc.setAttribute('r',source?source.radius:0);if(source){disc.setAttribute('cx',source.position[0]);disc.setAttribute('cy',source.position[1]);}
for(const a of svg.querySelectorAll('[data-node]')){const id=a.dataset.node;a.classList.toggle('connected',!!analysis.connected[id]);a.classList.toggle('covered',!!analysis.granted_by[id]);a.classList.toggle('eligible',!!analysis.eligible_nodes[id]);a.classList.toggle('remote',analysis.remote_nodes.includes(id));a.classList.toggle('selected',id===selectedNode);}
const active=Object.keys(analysis.active_sources).length;
document.getElementById('tree-status').textContent=active?`源孔有效 · 覆盖 ${Object.keys(analysis.granted_by).length} 个小/显著天赋；${Object.keys(analysis.eligible_nodes).length} 个节点当前可分配。${mode.value==='with_remote'?'已加入远程点 '+sample.remote_example+'。':''}`:'源孔未物理连接到起点，寻枝覆盖不生效。此配置不合法。';
if(selectedNode){const p=data.passives[selectedNode];const panel=document.getElementById('tree-selection');panel.replaceChildren();const name=document.createElement('strong');name.textContent=p.name+' · '+selectedNode;const info=document.createElement('p');info.textContent=analysis.connected[selectedNode]?'已分配且连接起点':analysis.remote_nodes.includes(selectedNode)?'已分配的远程点':analysis.eligible_nodes[selectedNode]?'当前可分配（仍消耗天赋点）':'当前不可分配';const a=document.createElement('a');a.href='#passives-'+selectedNode;a.textContent='打开完整天赋条目 ↗';panel.append(name,info,a);}
}
choice.addEventListener('change',renderTree);mode.addEventListener('change',renderTree);
svg.addEventListener('click',e=>{const node=e.target.closest('[data-node]');if(!node)return;e.preventDefault();selectedNode=node.dataset.node;renderTree();});
document.addEventListener('click',e=>{const same=e.target.closest('a[href]');if(same&&same.getAttribute('href')===location.hash&&!same.hasAttribute('data-node'))navigate();const a=e.target.closest('[data-tree-node]');if(a){selectedNode=a.dataset.treeNode;renderTree();}});
function setZoom(value){zoom=Math.min(3,Math.max(1,value));svg.style.width=zoom*100+'%';}
document.getElementById('zoom-in').addEventListener('click',()=>setZoom(zoom+.5));document.getElementById('zoom-out').addEventListener('click',()=>setZoom(zoom-.5));document.getElementById('zoom-reset').addEventListener('click',()=>setZoom(1));
refreshFacets();renderTree();navigate();
})();
