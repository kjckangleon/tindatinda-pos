import React, { useEffect, useRef, useState } from 'react';
import { BrowserMultiFormatReader, type IScannerControls } from '@zxing/browser';

type CameraTrack = MediaStreamTrack & {
 getCapabilities(): MediaTrackCapabilities & { focusMode?: string[]; zoom?: { min: number; max: number; step?: number }; torch?: boolean };
 applyConstraints(constraints: MediaTrackConstraints & { advanced?: Array<MediaTrackConstraintSet & { focusMode?: string; zoom?: number; torch?: boolean; pointsOfInterest?: Array<{x:number;y:number}> }> }): Promise<void>;
};
type Props = { onDetected: (code: string) => void; onClose: () => void; title?: string };

export function CameraBarcodeScanner({ onDetected, onClose, title = 'Scan barcode' }: Props) {
 const videoRef = useRef<HTMLVideoElement>(null);
 const detectedRef = useRef(onDetected);
 detectedRef.current = onDetected;
 const [camera, setCamera] = useState('');
 const [devices, setDevices] = useState<MediaDeviceInfo[]>([]);
 const [error, setError] = useState('');
 const [retry, setRetry] = useState(0);
 const [track, setTrack] = useState<CameraTrack | null>(null);
 const [zoom, setZoom] = useState(1);
 const [zoomRange, setZoomRange] = useState<{min:number;max:number}|null>(null);
 const [focusModes, setFocusModes] = useState<string[]>([]);
 const [focus, setFocus] = useState('');
 const [torchSupported, setTorchSupported] = useState(false);
 const [torch, setTorch] = useState(false);
 const [busy, setBusy] = useState(true);
 const lastRead = useRef('');
 useEffect(() => {
  let disposed = false;
  let controls: IScannerControls | null = null;
  const element = videoRef.current;
  async function start() {
   setBusy(true); setError(''); setTrack(null); setZoomRange(null); setFocusModes([]); setTorchSupported(false); setTorch(false); lastRead.current = '';
   if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
    setError('Camera requires HTTPS or localhost and a supported browser.'); setBusy(false); return;
   }
   try {
    const reader = new BrowserMultiFormatReader();
    controls = await reader.decodeFromConstraints({
     audio: false,
     video: camera ? { deviceId: { exact: camera } } : { facingMode: { ideal: 'environment' } }
    }, element!, result => {
     if (disposed || !result) return;
     const code = result.getText().trim();
     if (!code || code === lastRead.current) return;
     lastRead.current = code;
     detectedRef.current(code);
    });
    if (disposed) { controls.stop(); return; }
    const stream = element?.srcObject;
    const activeTrack = stream instanceof MediaStream ? stream.getVideoTracks()[0] as CameraTrack | undefined : undefined;
    if (activeTrack) {
     setTrack(activeTrack);
     const capabilities = activeTrack.getCapabilities?.() as (MediaTrackCapabilities & { focusMode?: string[]; zoom?: { min: number; max: number; step?: number }; torch?: boolean }) | undefined;
     if (capabilities?.zoom && capabilities.zoom.max > capabilities.zoom.min) {
      setZoomRange({ min: capabilities.zoom.min, max: capabilities.zoom.max });
      const settings = activeTrack.getSettings() as MediaTrackSettings & { zoom?: number };
      setZoom(settings.zoom ?? capabilities.zoom.min);
     }
     const modes = capabilities?.focusMode ?? [];
     setFocusModes(modes);
     if (modes.includes('continuous')) {
      try { await activeTrack.applyConstraints({ advanced: [{ focusMode: 'continuous' }] }); setFocus('continuous'); }
      catch { /* Some devices advertise focus but reject the constraint. */ }
     }
     setTorchSupported(capabilities?.torch === true);
    }
    const found = await BrowserMultiFormatReader.listVideoInputDevices();
    if (!disposed) setDevices(found);
   } catch (e) {
    if (!disposed) {
     const name = e instanceof DOMException ? e.name : '';
     setError(name === 'NotAllowedError' ? 'Camera access denied. Allow camera permission in browser settings and retry.'
      : name === 'NotFoundError' ? 'No camera found. Connect a webcam or use manual barcode entry.'
      : e instanceof Error ? e.message : 'Unable to start camera.');
    }
   } finally { if (!disposed) setBusy(false); }
  }
  void start();
  return () => {
   disposed = true;
   controls?.stop();
   if (element?.srcObject instanceof MediaStream) (element.srcObject as MediaStream).getTracks().forEach(t => t.stop());
  };
 }, [camera, retry]);
 async function updateFocus(mode: string) {
  if (!track) return;
  try { await track.applyConstraints({ advanced: [{ focusMode: mode }] }); setFocus(mode); setError(''); }
  catch { setError('This camera does not support changing focus mode.'); }
 }
 async function updateZoom(value: number) {
  if (!track) return;
  try { await track.applyConstraints({ advanced: [{ zoom: value }] }); setZoom(value); setError(''); }
  catch { setError('Zoom control is unavailable on this camera.'); }
 }
 async function updateTorch() {
  if (!track) return;
  try { await track.applyConstraints({ advanced: [{ torch: !torch }] }); setTorch(!torch); setError(''); }
  catch { setError('Flashlight control is unavailable on this camera.'); }
 }
 async function tapToFocus(e: React.MouseEvent<HTMLVideoElement>) {
  if (!track || !focusModes.includes('manual')) return;
  const bounds = e.currentTarget.getBoundingClientRect();
  const x = (e.clientX - bounds.left) / bounds.width;
  const y = (e.clientY - bounds.top) / bounds.height;
  try { await track.applyConstraints({ advanced: [{ focusMode: 'manual', pointsOfInterest: [{ x, y }] }] }); setFocus('manual'); }
  catch { setError('Tap-to-focus is not supported by this camera. Try continuous focus.'); }
 }
 return <section className="panel" aria-label="Camera barcode scanner" style={{ marginTop: 12 }}>
  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
   <strong>{title}</strong><button type="button" onClick={onClose}>Close camera</button>
  </div>
  <video ref={videoRef} autoPlay playsInline muted onClick={tapToFocus} aria-label="Live barcode camera preview"
   style={{ width: '100%', maxHeight: 360, objectFit: 'contain', background: '#111', borderRadius: 8, marginTop: 12 }} />
  {busy && <p role="status">Starting camera…</p>}
  {error && <p role="alert" className="error">{error}</p>}
  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 8, alignItems: 'center' }}>
   {devices.length > 1 && <label>Camera <select aria-label="Select camera" value={camera} onChange={e => setCamera(e.target.value)}>
    <option value="">Default / rear camera</option>{devices.map((d,i) => <option key={d.deviceId} value={d.deviceId}>{d.label || 'Camera ' + (i+1)}</option>)}
   </select></label>}
   {focusModes.length > 0 && <label>Focus <select aria-label="Focus mode" value={focus} onChange={e => void updateFocus(e.target.value)}>
    <option value="">Camera default</option>{focusModes.map(mode => <option key={mode} value={mode}>{mode === 'continuous' ? 'Auto / continuous' : mode === 'single-shot' ? 'Single focus' : mode === 'manual' ? 'Manual / tap' : mode}</option>)}
   </select></label>}
   {zoomRange && <label>Zoom {zoom.toFixed(1)}× <input aria-label="Camera zoom" type="range" min={zoomRange.min} max={zoomRange.max} step="0.1" value={zoom} onChange={e => void updateZoom(Number(e.target.value))}/></label>}
   {torchSupported && <button type="button" onClick={() => void updateTorch()}>{torch ? 'Flashlight off' : 'Flashlight on'}</button>}
   <button type="button" onClick={() => setRetry(x => x+1)}>Retry camera</button>
  </div>
  <p className="muted small">Hold the barcode steady in good light. Auto-focus, tap-to-focus, zoom and flashlight appear only when supported by the selected camera and browser. You can always enter the barcode manually.</p>
 </section>;
}
