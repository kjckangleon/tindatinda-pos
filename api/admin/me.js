import { createClient } from '@supabase/supabase-js';
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');
 if(req.method!=='GET')return res.status(405).json({error:'Method not allowed'});
 const url=process.env.VITE_SUPABASE_URL,publicKey=process.env.VITE_SUPABASE_ANON_KEY,secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!publicKey)return res.status(503).json({error:'Missing Supabase public configuration',code:'CONFIG_MISSING'});
 const token=(req.headers.authorization||'').replace(/^Bearer /,'');
 if(!token)return res.status(401).json({error:'Sign in required',code:'TOKEN_MISSING'});
 const client=createClient(url,publicKey,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:'Bearer '+token}}});
 const {data:auth,error:authError}=await client.auth.getUser(token);
 if(authError||!auth.user)return res.status(401).json({error:'Session rejected by Supabase',code:'SESSION_INVALID'});
 // Query only the signed-in user's own row. RLS already permits this.
 const {data:ownRole,error:ownError}=await client.from('platform_admins').select('user_id').eq('user_id',auth.user.id).maybeSingle();
 if(ownError)return res.status(500).json({error:'Authenticated role lookup failed',code:'ROLE_READ_FAILED',detail:ownError.code||'DATABASE_ERROR'});
 if(!ownRole)return res.status(200).json({isPlatformAdmin:false,code:'NO_MATCHING_ROLE'});
 return res.status(200).json({isPlatformAdmin:true,code:'VERIFIED'});
}
