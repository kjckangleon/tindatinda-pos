import {useCallback,useEffect,useMemo,useState} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';

type Expense={id:string;expense_date:string;details:string;amount_cents:number;created_at:string};
const peso=(c:number)=>new Intl.NumberFormat('en-PH',{style:'currency',currency:'PHP'}).format(c/100);
const todayPH=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Manila',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());

export default function IceExpenses({client,storeId,canEdit,start,end,onTotalChange}:{client:SupabaseClient;storeId:string;canEdit:boolean;start:string;end:string;onTotalChange:(total:number)=>void}){
 const [items,setItems]=useState<Expense[]>([]),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState('');
 const [date,setDate]=useState(todayPH),[details,setDetails]=useState(''),[amount,setAmount]=useState(''),[editing,setEditing]=useState<string|null>(null);
 const load=useCallback(async()=>{setLoading(true);setError('');const {data,error}=await client.from('ice_expenses').select('id,expense_date,details,amount_cents,created_at').eq('store_id',storeId).order('expense_date',{ascending:false}).limit(5000);if(error)setError(error.message);else setItems(data??[]);setLoading(false)},[client,storeId]);
 useEffect(()=>{void load()},[load]);
 const filtered=useMemo(()=>items.filter(x=>(!start||x.expense_date>=start)&&(!end||x.expense_date<=end)),[items,start,end]);
 const total=useMemo(()=>filtered.reduce((sum,x)=>sum+x.amount_cents,0),[filtered]);
 useEffect(()=>{onTotalChange(total)},[total,onTotalChange]);
 const reset=()=>{setEditing(null);setDate(todayPH());setDetails('');setAmount('')};
 async function save(e:React.FormEvent){e.preventDefault();if(!canEdit)return;setSaving(true);setError('');setNotice('');try{
 const value=Number(amount),cents=Math.round(value*100);
 if(!date||!/^\d{4}-\d{2}-\d{2}$/.test(date))throw new Error('Select an expense date');
 if(!details.trim()||details.trim().length>500)throw new Error('Enter expense details (up to 500 characters)');
 if(!Number.isFinite(value)||!Number.isSafeInteger(cents)||cents<=0||cents>100000000000)throw new Error('Enter a valid amount greater than zero');
 const fields={expense_date:date,details:details.trim(),amount_cents:cents};
 const response=editing?await client.from('ice_expenses').update(fields).eq('store_id',storeId).eq('id',editing):await client.from('ice_expenses').insert({...fields,store_id:storeId});
 if(response.error)throw response.error;
 reset();setNotice(editing?'Expense updated':'Expense saved');await load();
 }catch(err){setError(err instanceof Error?err.message:'Unable to save expense')}finally{setSaving(false)}}
 async function remove(item:Expense){if(!canEdit||!window.confirm('Delete this expense: '+item.details+' ('+peso(item.amount_cents)+')?'))return;setSaving(true);setError('');const {error}=await client.from('ice_expenses').delete().eq('store_id',storeId).eq('id',item.id);if(error)setError(error.message);else{setNotice('Expense deleted');await load()}setSaving(false)}
 return <section className="panel ice-report"><h2>Daily Expenses</h2><p className="muted small">Expenses follow the From / To dates selected above. Profit = sales minus expenses. This is a simple operating profit estimate, not a full accounting profit calculation.</p>
 {error&&<p className="error" role="alert">{error}</p>}{notice&&<p className="ice-notice" role="status">{notice}</p>}
 <div className="report-summary"><div><strong>{peso(total)}</strong><small>Expenses in selected period</small></div><div><strong>{filtered.length}</strong><small>Expense entries</small></div></div>
 {canEdit&&<form className="ice-form ice-edit" onSubmit={save}><h3>{editing?'Edit expense':'Add expense'}</h3><label>Date<input required type="date" value={date} onChange={e=>setDate(e.target.value)}/></label><label>Details<input required maxLength={500} value={details} onChange={e=>setDetails(e.target.value)} placeholder="e.g. Electricity, fuel, delivery, wages"/></label><label>Amount (₱)<input required type="number" inputMode="decimal" min="0.01" step="0.01" value={amount} onChange={e=>setAmount(e.target.value)}/></label><div className="ice-actions"><button type="submit" disabled={saving}>{saving?'Saving…':editing?'Save changes':'Save expense'}</button>{editing&&<button type="button" onClick={reset}>Cancel</button>}</div></form>}
 <h3>Expense history</h3>{loading?<p className="muted">Loading expenses…</p>:filtered.length===0?<p className="muted">No expenses recorded for this date range.</p>:filtered.map(x=><div className="ice-sale-row" key={x.id}><div className="ice-sale-details"><strong>{x.details}</strong><span className="muted small">{x.expense_date}</span></div><strong>{peso(x.amount_cents)}</strong>{canEdit&&<div className="ice-actions"><button type="button" disabled={saving} onClick={()=>{setEditing(x.id);setDate(x.expense_date);setDetails(x.details);setAmount((x.amount_cents/100).toFixed(2))}}>Edit</button><button type="button" disabled={saving} onClick={()=>void remove(x)}>Delete</button></div>}</div>)}
 <button type="button" onClick={()=>void load()} disabled={loading}>Refresh expenses</button>
 </section>
}