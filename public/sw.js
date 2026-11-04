const CACHE_VERSION='fumacraft-v11';
const CORE_ASSETS=['/','/icon.svg','/icon-192.png','/manifest.json'];
self.addEventListener('install',event=>{
 event.waitUntil((async()=>{
  const cache=await caches.open(CACHE_VERSION);
  await cache.addAll(CORE_ASSETS);
  await self.skipWaiting();
 })());
});
self.addEventListener('activate',event=>{
 event.waitUntil((async()=>{
  const keys=await caches.keys();
  await Promise.all(keys.filter(key=>key!==CACHE_VERSION).map(key=>caches.delete(key)));
  await self.clients.claim();
 })());
});
self.addEventListener('fetch',event=>{
 const request=event.request;
 const url=new URL(request.url);
 if(request.method!=='GET'||url.origin!==self.location.origin)return;
 event.respondWith((async()=>{
  try{
   const response=await fetch(request,{cache:request.mode==='navigate'?'no-store':'no-cache'});
   if(response&&response.ok&&request.method==='GET'){
    const cache=await caches.open(CACHE_VERSION);
    cache.put(request,response.clone()).catch(()=>{});
   }
   return response;
  }catch(error){
   const cached=await caches.match(request);
   if(cached)return cached;
   if(request.mode==='navigate')return (await caches.match('/'))||Response.error();
   return Response.error();
  }
 })());
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 const target=(event.notification.data&&event.notification.data.url)||'/painel';
 event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async clients=>{
  for(const client of clients){if('focus' in client){await client.navigate(target);return client.focus()}}
  return self.clients.openWindow(target);
 }));
});
self.addEventListener('push',event=>{
 let data={};try{data=event.data.json()}catch(error){data={title:'Fumacraft',body:event.data&&event.data.text()}}
 event.waitUntil(self.registration.showNotification(data.title||'Fumacraft',{
  body:data.body||'',icon:'/icon-192.png',badge:'/icon-192.png',
  data:{url:data.url||'/painel'},vibrate:[200,100,200],requireInteraction:true
 }));
});