import {useCallback,useEffect,useMemo,useState} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';
type Store={id:string;name:string};
type Sale={id:string;store_id:string;created_at:string;total_cents:number};
type StoreRow={id:string;name:string;products:number;outOfStock:number;transactions:number;revenue:number};
const phDate=(date:string)=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(date));
const php=(c:number)=>'₱'+(c/100).toLocaleString('en-PH',{minimumFractionDigits:2,maximumFractionDigits:2});
export default function PlatformAudit({client,stores}:{client:SupabaseClient;stores:Store[]}){
 const [rows,setRows]=useState<StoreRow[]>([]),[sales,setSales]=useState<Sale[]>([]),[loading,setLoading]=useState(false),[error,setError]=useState(''),[checked,setChecked]=useState(''),[warnings,setWarnings]=useState<string[]>([]);
 const refresh=useCallback(async()=>{setLoading(true);setError('');try{
  const since=new Date(Date.now()-30*86400000).toISOString();
  const results:StoreRow[]=[];const allSales:Sale[]=[];const notes:string[]=[];
  for(const store of stores){
   const [products,empty,retail,ice]=await Promise.all([
    client.from('products').select('id',{count:'exact',head:true}).eq('store_id',store.id),
    client.from('products').select('id',{count:'exact',head:true}).eq('store_id',store.id).lte('stock',0),
    client.from('sales').select('id,store_id,created_at,total_cents').eq('store_id',store.id).gte('created_at',since).order('created_at',{ascending:false}).limit(1000),
    client.from('ice_sales').select('id,store_id,created_at,total_cents').eq('store_id',store.id).is('voided_at',null).gte('created_at',since).order('created_at',{ascending:false}).limit(1000)
   ]);
   const failures=[products.error,empty.error,retail.error,ice.error].filter(Boolean);
   if(failures.length)throw new Error('Audit data unavailable for '+store.name+': '+failures[0]?.message);
   const recent=[...(retail.data??[]),...(ice.data??[])];
   if((retail.data??[]).length===1000||(ice.data??[]).length===1000)notes.push(store.name+': sales sample reached 1,000 rows; 30-day totals may be incomplete');
   allSales.push(...recent);
   results.push({id:store.id,name:store.name,products:products.count??0,outOfStock:empty.count??0,transactions:recent.length,revenue:recent.reduce((sum,s)=>sum+Number(s.total_cents),0)});
  }
  setRows(results);setSales(allSales);setWarnings(notes);setChecked(new Date().toISOString());
 }catch(e){setError(e instanceof Error?e.message:'Audit read failed');setRows([]);setSales([]);setChecked('')}finally{setLoading(false)}},[client,stores]);
 useEffect(()=>{void refresh()},[refresh]);
 const trend=useMemo(()=>{const days=new Map<string,{count:number;revenue:number}>();for(const sale of sales){const day=phDate(sale.created_at);const row=days.get(day)??{count:0,revenue:0};row.count++;row.revenue+=Number(sale.total_cents);days.set(day,row)}return [...days.entries()].sort((a,b)=>a[0].localeCompare(b[0])).slice(-14)},[sales]);
 const max=Math.max(1,...trend.map(([,d])=>d.revenue));
 const totals=rows.reduce((a,r)=>({products:a.products+r.products,out:a.out+r.outOfStock,transactions:a.transactions+r.transactions,revenue:a.revenue+r.revenue}),{products:0,out:0,transactions:0,revenue:0});
 return <section className="panel"><h2>Platform Audit Dashboard</h2><p className="muted">Read-only operational snapshot for the last 30 days, in Philippine time. This is not yet an automated infrastructure performance audit.</p>
 <button type="button" className="icon-button" disabled={loading} onClick={()=>void refresh()}>{loading?'Checking…':'Refresh audit'}</button>
 {checked&&<p className="muted small">Last checked: {new Date(checked).toLocaleString('en-PH',{timeZone:'Asia/Manila'})}</p>}
 {error&&<p className="error" role="alert">{error}</p>}
 {warnings.map(w=><p key={w} className="error">{w}</p>)}
 <div className="report-summary"><div><strong>{rows.length}</strong><small>Stores checked</small></div><div><strong>{totals.products}</strong><small>Products</small></div><div><strong>{totals.out}</strong><small>Out of stock</small></div><div><strong>{totals.transactions}</strong><small>30-day sales</small></div><div><strong>{php(totals.revenue)}</strong><small>30-day revenue</small></div></div>
 <h3>Revenue trend · Last 14 recorded days</h3><div style={{display:'flex',gap:6,alignItems:'end',height:170,overflowX:'auto',padding:'12px 0'}} role="img" aria-label="Daily revenue chart">{trend.map(([day,d])=><div key={day} style={{flex:'1 0 34px',height:'100%',display:'flex',flexDirection:'column',justifyContent:'end',alignItems:'center',gap:5}} title={day+' · '+php(d.revenue)+' · '+d.count+' sales'}><small style={{fontSize:10}}>{php(d.revenue)}</small><div style={{height:Math.max(2,d.revenue/max*110),background:'#38bdf8',width:'75%',borderRadius:4}}/><small style={{fontSize:10}}>{day.slice(5)}</small></div>)}</div>
 <h3>Store breakdown</h3><div style={{overflowX:'auto'}}><table style={{width:'100%',minWidth:580}}><thead><tr><th>Store</th><th>Products</th><th>Out of stock</th><th>Sales (30d)</th><th>Revenue (30d)</th></tr></thead><tbody>{rows.map(r=><tr key={r.id}><td>{r.name}</td><td>{r.products}</td><td>{r.outOfStock}</td><td>{r.transactions}</td><td>{php(r.revenue)}</td></tr>)}</tbody></table></div>
 <h3>Infrastructure audit coverage</h3><p className="muted small">Pending integration: Vercel build/runtime failures and latency, Supabase query latency/connection health/index usage, GitHub CI results, dependency vulnerabilities, and weekly historical snapshots. No health claims are made for these unmeasured areas.</p>
 <p className="muted small">The dashboard reads store-scoped data under the signed-in user's Supabase permissions. No records are created or modified.</p>
 </section>;
}
