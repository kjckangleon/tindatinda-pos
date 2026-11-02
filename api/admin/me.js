import { createClient } from '@supabase/supabase-js';
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');
 if(req.method!=='GET')return res.status(405).json({error:'Method not allowed'});
 const url=process.env.VITE_SUPABASE_URL, publicKey=process.env.VITE_SUPABASE_ANON_KEY, secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!publicKey||!secret)return res.status(503).json({error:'Server authorization is not configured'});
 const token=(req.headers.authorization||'').replace(/^Bearer /,'');
 if(!token)return res.status(401).json({error:'Sign in required'});
 const client=createClient(url,publicKey,{auth:{persistSession:false}});
 const {data:auth,error:authError}=await client.auth.getUser(token);
 if(authError||!auth.user)return res.status(401).json({error:'Invalid session'});
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error}=await admin.from('platform_admins').select('user_id').eq('user_id',auth.user.id).maybeSingle();
 if(error)return res.status(500).json({error:'Could not verify platform role'});
 return res.status(200).json({isPlatformAdmin:Boolean(data)});
}