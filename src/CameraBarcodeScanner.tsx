import React, { useEffect, useRef, useState } from 'react';
import { BrowserMultiFormatReader, type IScannerControls } from '@zxing/browser';
export function CameraBarcodeScanner({onDetected,onClose}:{onDetected:(code:string)=>void;onClose:()=>void}) {
 const video=useRef<HTMLVideoElement>(null);
 const detectedRef=useRef(onDetected);
 detectedRef.current=onDetected;
 const [error,setError]=useState('');
 const [camera,setCamera]=useState('');
 const [devices,setDevices]=useState<MediaDeviceInfo[]>([]);
 const [retry,setRetry]=useState(0);
 useEffect(()=>{
  let disposed=false;
  let controls:IScannerControls|null=null;
  const element=video.current;
  async function start(){
   if(!window.isSecureContext||!navigator.mediaDevices?.getUserMedia){setError('Camera requires HTTPS or localhost and browser camera support.');return;}
   try{
    setError('');
    const reader=new BrowserMultiFormatReader();
    controls=await reader.decodeFromConstraints({audio:false,video:camera?{deviceId:{exact:camera}}:{facingMode:{ideal:'environment'}}},element!,result=>{
     if(!disposed&&result)detectedRef.current(result.getText());
    });
    if(disposed){controls.stop();return;}
    const found=await BrowserMultiFormatReader.listVideoInputDevices();
    if(!disposed)setDevices(found);
   }catch(e){
    if(!disposed)setError(e instanceof Error?e.message:'Unable to access camera. Check permissions or connect a webcam.');
   }
  }
  void start();
  return ()=>{disposed=true;controls?.stop();if(element?.srcObject instanceof MediaStream)(element.srcObject as MediaStream).getTracks().forEach(t=>t.stop());};
 },[camera,retry]);
 return <section className="panel" aria-label="Camera barcode scanner" style={{marginTop:12}}>
  <div style={{display:'flex',justifyContent:'space-between',gap:8,alignItems:'center'}}><strong>Camera barcode scanner</strong><button type="button" onClick={onClose}>Close camera</button></div>
  <video ref={video} autoPlay playsInline muted style={{width:'100%',maxHeight:320,objectFit:'contain',background:'#111',borderRadius:8,marginTop:12}} aria-label="Camera preview"/>
  {error&&<p role="alert" className="error">{error}</p>}
  <div style={{display:'flex',flexWrap:'wrap',gap:8,marginTop:8}}>
   {devices.length>1&&<select aria-label="Select camera" value={camera} onChange={e=>setCamera(e.target.value)}><option value="">Default / rear camera</option>{devices.map((d,i)=><option key={d.deviceId} value={d.deviceId}>{d.label||'Camera '+(i+1)}</option>)}</select>}
   <button type="button" onClick={()=>setRetry(x=>x+1)}>Retry camera</button>
  </div>
  <p className="muted small">Allow camera permission. On laptops and desktops, connect a webcam. USB barcode scanners work with the barcode input.</p>
 </section>;
}
