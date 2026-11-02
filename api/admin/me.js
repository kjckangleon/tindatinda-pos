import { createClient } from '@supabase/supabase-js';
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');
 if(req.method!=='GET')return res.status(405).json({error:'Method not allowed'});
 const url=process.env.VITE_SUPABASE_URL,publicKey=process.env.VITE_SUPABASE_ANON_KEY,secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!publicKey)return res.status(503).json({error:'Missing Supabase public configuration',code:'CONFIG_MISSING'});
 const token=(req.headers.authorization||'').replace(/^Bearer /,'');
 if(!token)return res.status(401).json({error:'Sign in required',code:'TOKEN_MISSING'});
 const client=createClient(url,publicKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:auth,error:authError}=await client.auth.getUser(token);
 if(authError||!auth.user)return res.status(401).json({error:'Session rejected by Supabase',code:'SESSION_INVALID'});
 // Query only the signed-in user's own row. RLS already permits this.
 const {data:ownRole,error:ownError}=await client.from('platform_admins').select('user_id').eq('user_id',auth.user.id).maybeSingle();
 if(ownError)return res.status(500).json({error:'Authenticated role lookup failed',code:'ROLE_READ_FAILED',detail:ownError.code||'DATABASE_ERROR'});
 if(!ownRole)return res.status(200).json({isPlatformAdmin:false,code:'NO_MATCHING_ROLE'});
 if(!secret)return res.status(503).json({isPlatformAdmin:true,error:'Service role key missing; admin actions unavailable',code:'SERVICE_KEY_MISSING'});
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:serverRole,error:serverError}=await admin.from('platform_admins').select('user_id').eq('user_id',auth.user.id).maybeSingle();
 if(serverError)return res.status(503).json({isPlatformAdmin:true,error:'Server-side role verification failed; admin actions unavailable',code:'SERVICE_ROLE_FAILED',detail:serverError.code||'DATABASE_ERROR'});
 if(!serverRole)return res.status(503).json({isPlatformAdmin:true,error:'Service key cannot read matching admin row',code:'SERVICE_ROLE_NO_MATCH'});
 return res.status(200).json({isPlatformAdmin:true,code:'VERIFIED'});
}
