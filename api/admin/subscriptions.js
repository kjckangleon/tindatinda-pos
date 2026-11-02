import { createClient } from '@supabase/supabase-js';
const url=process.env.VITE_SUPABASE_URL,anon=process.env.VITE_SUPABASE_ANON_KEY,secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');
 if(!['GET','POST'].includes(req.method))return res.status(405).json({error:'Method not allowed'});
 if(!url||!anon||!secret)return res.status(503).json({error:'Service not configured'});
 const token=(req.headers.authorization||'').replace(/^Bearer /,'');
 if(!token)return res.status(401).json({error:'Sign in required'});
 const client=createClient(url,anon,{auth:{persistSession:false}});
 const {data:identity,error:authError}=await client.auth.getUser(token);
 if(authError||!identity.user)return res.status(401).json({error:'Invalid session'});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 if(req.method==='GET'&&req.query?.scope==='me'){
  const {data:subscription,error}=await db.from('user_subscriptions').select('plan,starts_at,expires_at').eq('user_id',identity.user.id).maybeSingle();
  if(error)return res.status(503).json({error:'Subscription database not configured'});
  return res.status(200).json({subscription:subscription||null});
 }
 const {data:role,error:roleError}=await db.from('platform_admins').select('user_id').eq('user_id',identity.user.id).maybeSingle();
 if(roleError||!role)return res.status(403).json({error:'Super Admin access required'});
 if(req.method==='GET'){
  const users=[];let page=1;
  while(page<=20){const {data,error}=await db.auth.admin.listUsers({page,perPage:100});if(error)return res.status(500).json({error:'Could not load users'});users.push(...data.users.map(u=>({id:u.id,email:u.email})));if(data.users.length<100)break;page++;}
  const {data:subscriptions,error}=await db.from('user_subscriptions').select('*');
  if(error)return res.status(503).json({error:'Run migration 003_user_subscriptions.sql in Supabase first'});
  return res.status(200).json({users,subscriptions});
 }
 const {userId,plan,amount,method,notes,customDays}=req.body||{};
 if(typeof userId!=='string'||!/^[0-9a-f-]{36}$/i.test(userId)||!['trial','monthly','quarterly','annual','lifetime','custom'].includes(plan))return res.status(400).json({error:'Invalid user or plan'});
 if(typeof amount!=='number'||!Number.isSafeInteger(amount)||amount<0||amount>1000000000)return res.status(400).json({error:'Amount must be a nonnegative integer in centavos'});
 if(typeof method!=='string'||method.length>60||typeof notes!=='string'||notes.length>500)return res.status(400).json({error:'Invalid payment details'});
 if(plan==='custom'&&(!Number.isInteger(customDays)||customDays<1||customDays>3650))return res.status(400).json({error:'Custom duration must be 1–3650 days'});
 const {data:target,error:targetError}=await db.auth.admin.getUserById(userId);
 if(targetError||!target?.user)return res.status(404).json({error:'User not found'});
 const {data:existing,error:readError}=await db.from('user_subscriptions').select('expires_at').eq('user_id',userId).maybeSingle();
 if(readError)return res.status(503).json({error:'Run migration 003_user_subscriptions.sql in Supabase first'});
 const now=new Date();const currentExpiry=existing?.expires_at?new Date(existing.expires_at):null;
 const start=currentExpiry&&currentExpiry>now&&plan!=='lifetime'?currentExpiry:now;
 let end=null;
 if(plan!=='lifetime'){const d=new Date(start);if(plan==='trial')d.setUTCDate(d.getUTCDate()+7);else if(plan==='monthly')d.setUTCMonth(d.getUTCMonth()+1);else if(plan==='quarterly')d.setUTCMonth(d.getUTCMonth()+3);else if(plan==='annual')d.setUTCFullYear(d.getUTCFullYear()+1);else d.setUTCDate(d.getUTCDate()+customDays);end=d.toISOString();}
 const record={user_id:userId,plan,starts_at:start.toISOString(),expires_at:end,amount_cents:amount,payment_method:method.trim()||'manual',notes:notes.trim(),updated_at:now.toISOString(),updated_by:identity.user.id};
 const {error:saveError}=await db.from('user_subscriptions').upsert(record);
 if(saveError)return res.status(500).json({error:'Could not save subscription'});
 const {error:ledgerError}=await db.from('subscription_payments').insert({user_id:userId,plan,amount_cents:amount,payment_method:record.payment_method,notes:record.notes,starts_at:record.starts_at,expires_at:end,recorded_by:identity.user.id});
 if(ledgerError)return res.status(500).json({error:'Subscription saved but payment history could not be recorded. Contact administrator.'});
 return res.status(200).json({subscription:record});
}