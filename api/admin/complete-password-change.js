import { createClient } from '@supabase/supabase-js';
const url=process.env.VITE_SUPABASE_URL,anon=process.env.VITE_SUPABASE_ANON_KEY,secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store, private');
 if(req.method!=='POST')return res.status(405).json({error:'Method not allowed'});
 if(!url||!anon||!secret)return res.status(503).json({error:'Service not configured'});
 const token=(req.headers.authorization||'').replace(/^Bearer /,'');
 if(!token)return res.status(401).json({error:'Sign in required'});
 const caller=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:identity,error:authError}=await caller.auth.getUser(token);
 if(authError||!identity.user)return res.status(401).json({error:'Invalid session'});
 const {password}=req.body||{};
 if(typeof password!=='string'||password.length<12||password.length>128)return res.status(400).json({error:'New password must be 12–128 characters'});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:target,error:lookupError}=await db.auth.admin.getUserById(identity.user.id);
 if(lookupError||!target?.user)return res.status(404).json({error:'Account not found'});
 if(target.user.app_metadata?.force_password_change!==true)return res.status(403).json({error:'Password reset is not pending'});
 const {error}=await db.auth.admin.updateUserById(identity.user.id,{password,app_metadata:{...target.user.app_metadata,force_password_change:false}});
 if(error)return res.status(500).json({error:'Password update failed'});
 return res.status(200).json({success:true});
}