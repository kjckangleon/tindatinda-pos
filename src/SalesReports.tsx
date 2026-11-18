import React, { useEffect, useMemo, useState } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';

type Sale = { id:string; store_id:string; total_cents:number; cash_cents:number; created_at:string };
type Line = { id:string; sale_id:string; product_id:string; qty:number; unit_price_cents:number };
type Product = { id:string; name:string };
const php=(value:number)=>new Intl.NumberFormat('en-PH',{style:'currency',currency:'PHP'}).format(value/100);
const localDay=(iso:string)=>new Date(iso).toLocaleDateString('en-CA',{timeZone:'Asia/Manila'});
export function SalesReports({client,storeId,storeName}:{client:SupabaseClient;storeId:string;storeName:string}){
 const [sales,setSales]=useState<Sale[]>([]);
 const [loading,setLoading]=useState(false);
 const [error,setError]=useState('');
 const [day,setDay]=useState(()=>localDay(new Date().toISOString()));
 const [endDay,setEndDay]=useState(()=>localDay(new Date().toISOString()));
 const [selected,setSelected]=useState<Sale|null>(null);
 const [lines,setLines]=useState<Line[]>([]);
 const [names,setNames]=useState<Record<string,string>>({});
 const [receiptError,setReceiptError]=useState('');
 useEffect(()=>{let cancelled=false;setSales([]);setSelected(null);setError('');if(!storeId)return;
  async function load(){setLoading(true);const all:Sale[]=[];let failure='';for(let offset=0;offset<5000;offset+=500){const {data,error}=await client.from('sales').select('id,store_id,total_cents,cash_cents,created_at').eq('store_id',storeId).order('created_at',{ascending:false}).order('id',{ascending:false}).range(offset,offset+499);if(error){failure=error.message;break}all.push(...(data??[]));if((data??[]).length<500)break}
   if(!cancelled){setSales(all);setError(failure);setLoading(false)}}
  void load();return()=>{cancelled=true};
 },[client,storeId]);
 const filtered=useMemo(()=>sales.filter(s=>localDay(s.created_at)>=day&&localDay(s.created_at)<=endDay),[sales,day,endDay]);
 const gross=filtered.reduce((n,s)=>n+Number(s.total_cents),0);
 function exportCsv(){if(!filtered.length||error)return;const rows=[['Sale ID','Date','Total PHP','Cash PHP'],...filtered.map(s=>[s.id,new Date(s.created_at).toLocaleString('en-PH',{timeZone:'Asia/Manila'}),(Number(s.total_cents)/100).toFixed(2),(Number(s.cash_cents)/100).toFixed(2)])];const csv=rows.map(row=>row.map(v=>'"'+String(v).replace(/"/g,'""')+'"').join(',')).join('\r\n');const url=URL.createObjectURL(new Blob(['\uFEFF',csv],{type:'text/csv;charset=utf-8'}));const link=document.createElement('a');link.href=url;link.download='sales-'+day+'-'+endDay+'.csv';link.click();window.setTimeout(()=>URL.revokeObjectURL(url),1000)}
 async function openReceipt(s:Sale){setReceiptError('');setSelected(null);const {data,error}=await client.from('sale_lines').select('id,sale_id,product_id,qty,unit_price_cents').eq('sale_id',s.id);
  if(error){setReceiptError(error.message);return}
  const ids=[...new Set((data??[]).map(x=>x.product_id))];
  const found=ids.length?await client.from('products').select('id,name').eq('store_id',storeId).in('id',ids):{data:[] as Product[],error:null};
  if(found.error){setReceiptError(found.error.message);return}
  setNames(Object.fromEntries((found.data??[]).map(p=>[p.id,p.name])));
  setLines(data??[]);setSelected(s);
 }
 return <section className="panel sales-report">
  <h2>Sales report</h2>
  <div className="report-dates"><label>From (Philippine time)<input aria-label="Sales date" type="date" value={day} max={endDay} onChange={e=>setDay(e.target.value)}/></label><label>To<input aria-label="End date" type="date" value={endDay} min={day} onChange={e=>setEndDay(e.target.value)}/></label><button type="button" disabled={loading||!filtered.length||!!error} onClick={exportCsv}>Export CSV</button></div>
  <div className="report-summary"><div><strong>{php(gross)}</strong><small>Sales total</small></div><div><strong>{filtered.length}</strong><small>Transactions</small></div><div><strong>{filtered.length?php(Math.round(gross/filtered.length)):'₱0.00'}</strong><small>Average sale</small></div></div>
  <p className="muted small">Loaded {sales.length} transactions for this store (maximum 5,000). If this limit is reached, totals and exports may be incomplete.</p>
  {loading&&<p role="status">Loading sales…</p>}{error&&<p role="alert" className="error">{error}</p>}
  {!loading&&!filtered.length&&<p>No sales found for this date.</p>}
  {filtered.map(s=><div className="item" key={s.id}><span>{new Date(s.created_at).toLocaleTimeString('en-PH',{timeZone:'Asia/Manila',hour:'numeric',minute:'2-digit'})} · #{s.id.slice(0,8)}</span><strong>{php(Number(s.total_cents))}</strong><button type="button" onClick={()=>void openReceipt(s)}>Receipt</button></div>)}
  {receiptError&&<p role="alert" className="error">{receiptError}</p>}
  {selected&&<div className="receipt-panel"><div className="receipt-print"><h2>{storeName}</h2><p>Sales receipt · #{selected.id.slice(0,8)}</p><p>{new Date(selected.created_at).toLocaleString('en-PH',{timeZone:'Asia/Manila'})}</p>
    {lines.map(line=><div className="item" key={line.id}><span>{names[line.product_id]??'Product '+line.product_id.slice(0,8)} · {line.qty} × {php(line.unit_price_cents)}</span><strong>{php(line.qty*line.unit_price_cents)}</strong></div>)}
    <div className="item"><strong>Total</strong><strong>{php(Number(selected.total_cents))}</strong></div><div className="item"><span>Cash</span><span>{php(Number(selected.cash_cents))}</span></div><div className="item"><span>Change</span><span>{php(Number(selected.cash_cents)-Number(selected.total_cents))}</span></div><p>Thank you for shopping!</p></div>
    <div className="receipt-actions"><button type="button" onClick={()=>window.print()}>Print receipt</button><button type="button" onClick={()=>setSelected(null)}>Close receipt</button></div>
   </div>}
 </section>;
}
