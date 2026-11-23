import React, { useEffect, useMemo, useState } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';

type Sale = { id:string; store_id:string; total_cents:number; cash_cents:number; created_at:string };
type Line = { id:string; sale_id:string; product_id:string; qty:number; unit_price_cents:number };
type Product = { id:string; name:string };
const php=(value:number)=>new Intl.NumberFormat('en-PH',{style:'currency',currency:'PHP'}).format(value/100);
const localDay=(iso:string)=>new Date(iso).toLocaleDateString('en-CA',{timeZone:'Asia/Manila'});
export function SalesReports({client,storeId,storeName}:{client:SupabaseClient;storeId:string;storeName:string}){
 const [sales,setSales]=useState<Sale[]>([]);
 const [visibleCount,setVisibleCount]=useState(3);
 const [loading,setLoading]=useState(false);
 const [error,setError]=useState('');
 const [day,setDay]=useState(()=>localDay(new Date().toISOString()));
 const [endDay,setEndDay]=useState(()=>localDay(new Date().toISOString()));
 const [selected,setSelected]=useState<Sale|null>(null);
 const [lines,setLines]=useState<Line[]>([]);
 const [names,setNames]=useState<Record<string,string>>({});
 const [receiptError,setReceiptError]=useState('');
 const [saleItems,setSaleItems]=useState<Record<string,string>>({});
 const [itemsLoading,setItemsLoading]=useState(false);
 const [itemsError,setItemsError]=useState('');
 useEffect(()=>{let cancelled=false;setSales([]);setSelected(null);setError('');if(!storeId)return;
  async function load(){setLoading(true);const all:Sale[]=[];let failure='';for(let offset=0;offset<5000;offset+=500){const {data,error}=await client.from('sales').select('id,store_id,total_cents,cash_cents,created_at').eq('store_id',storeId).order('created_at',{ascending:false}).order('id',{ascending:false}).range(offset,offset+499);if(error){failure=error.message;break}all.push(...(data??[]));if((data??[]).length<500)break}
   if(!cancelled){setSales(all);setError(failure);setLoading(false)}}
  void load();return()=>{cancelled=true};
 },[client,storeId]);
 useEffect(()=>{setVisibleCount(3);setSelected(null)},[storeId,day,endDay]);
 const filtered=useMemo(()=>sales.filter(s=>localDay(s.created_at)>=day&&localDay(s.created_at)<=endDay),[sales,day,endDay]);
 useEffect(()=>{let cancelled=false;setSaleItems({});setItemsError('');if(!storeId||!filtered.length){setItemsLoading(false);return}const load=async()=>{setItemsLoading(true);try{const allLines:Line[]=[];for(let i=0;i<filtered.length;i+=150){const ids=filtered.slice(i,i+150).map(s=>s.id);const {data,error}=await client.from('sale_lines').select('id,sale_id,product_id,qty,unit_price_cents').in('sale_id',ids);if(error)throw error;allLines.push(...(data??[]))}const ids=[...new Set(allLines.map(l=>l.product_id))];const productNames:Record<string,string>={};for(let i=0;i<ids.length;i+=150){const {data,error}=await client.from('products').select('id,name').eq('store_id',storeId).in('id',ids.slice(i,i+150));if(error)throw error;for(const p of data??[])productNames[p.id]=p.name}const grouped:Record<string,string[]>={};for(const l of allLines)(grouped[l.sale_id]??=[]).push((productNames[l.product_id]??'Product '+l.product_id.slice(0,8))+' ×'+l.qty);if(!cancelled)setSaleItems(Object.fromEntries(Object.entries(grouped).map(([id,items])=>[id,items.join(', ')])))}catch(e){if(!cancelled)setItemsError(e instanceof Error?e.message:'Could not load sale items')}finally{if(!cancelled)setItemsLoading(false)}};void load();return()=>{cancelled=true}},[client,storeId,filtered]);
 const gross=filtered.reduce((n,s)=>n+Number(s.total_cents),0);
 const daily=useMemo(()=>{const totals=new Map<string,{date:string,total:number,count:number}>();for(const sale of filtered){const date=localDay(sale.created_at);const prev=totals.get(date)??{date,total:0,count:0};prev.total+=Number(sale.total_cents);prev.count++;totals.set(date,prev)}return [...totals.values()].sort((a,b)=>a.date.localeCompare(b.date))},[filtered]);
 const peak=Math.max(1,...daily.map(x=>x.total));
 const busiest=daily.reduce<{date:string;total:number;count:number}|null>((best,x)=>!best||x.total>best.total?x:best,null);

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
  {daily.length>0&&<div className="sales-trends"><h3>Daily sales trend</h3><div className="trend-bars" role="img" aria-label="Sales totals by date">{daily.map(d=><div className="trend-day" key={d.date} title={d.date+': '+php(d.total)+' from '+d.count+' transactions'}><strong>{php(d.total)}</strong><div className="trend-track"><div className="trend-fill" style={{height:Math.max(3,Math.round(d.total/peak*100))+'%'}}/></div><small>{d.date.slice(5)}</small></div>)}</div><p className="muted small">Highest sales day: {busiest?.date} ({php(busiest?.total??0)}). Based on the selected date range.</p></div>}
  <p className="muted small">Loaded {sales.length} transactions for this store (maximum 5,000). If this limit is reached, totals and exports may be incomplete.</p>
  {loading&&<p role="status">Loading sales…</p>}{error&&<p role="alert" className="error">{error}</p>}
  {!loading&&!filtered.length&&<p>No sales found for this date.</p>}
  {itemsError&&<p role="alert" className="error">Product details unavailable: {itemsError}</p>}
  {filtered.slice(0,visibleCount).map(s=><div className="item sale-transaction" key={s.id}><div className="sale-transaction-info"><strong>{saleItems[s.id]??(itemsLoading?'Loading products…':'Products unavailable')}</strong><span className="muted small">{new Date(s.created_at).toLocaleTimeString('en-PH',{timeZone:'Asia/Manila',hour:'numeric',minute:'2-digit'})} · Transaction #{s.id.slice(0,8)}</span></div><strong className="sale-transaction-total">{php(Number(s.total_cents))}</strong><button className="icon-button" type="button" onClick={()=>void openReceipt(s)}>View receipt</button></div>)}
  {filtered.length>visibleCount&&<button type="button" onClick={()=>setVisibleCount(n=>Math.min(n+10,filtered.length))}>Show 10 more transactions ({filtered.length-visibleCount} remaining)</button>}
  {filtered.length>3&&visibleCount>3&&<button type="button" onClick={()=>setVisibleCount(3)}>Show latest 3 only</button>}
  {receiptError&&<p role="alert" className="error">{receiptError}</p>}
  {selected&&<div className="receipt-panel"><div className="receipt-print"><h2>{storeName}</h2><p>Sales receipt · #{selected.id.slice(0,8)}</p><p>{new Date(selected.created_at).toLocaleString('en-PH',{timeZone:'Asia/Manila'})}</p>
    {lines.map(line=><div className="item" key={line.id}><span>{names[line.product_id]??'Product '+line.product_id.slice(0,8)} · {line.qty} × {php(line.unit_price_cents)}</span><strong>{php(line.qty*line.unit_price_cents)}</strong></div>)}
    <div className="item"><strong>Total</strong><strong>{php(Number(selected.total_cents))}</strong></div><div className="item"><span>Cash</span><span>{php(Number(selected.cash_cents))}</span></div><div className="item"><span>Change</span><span>{php(Number(selected.cash_cents)-Number(selected.total_cents))}</span></div><p>Thank you for shopping!</p></div>
    <div className="receipt-actions"><button type="button" onClick={()=>window.print()}>Print receipt</button><button type="button" onClick={()=>setSelected(null)}>Close receipt</button></div>
   </div>}
 </section>;
}
