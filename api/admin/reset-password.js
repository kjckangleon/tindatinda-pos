import { createClient } from '@supabase/supabase-js';
import { randomBytes } from 'node:crypto';

const url=process.env.VITE_SUPABASE_URL;
const anon=process.env.VITE_SUPABASE_ANON_KEY;
const secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store, private');
 if(req.method!=='POST')return res.status(405).json({error:'Method not allowed'});
 if(!url||!anon||!secret)return res.status(503).json({error:'Password reset service not configured'});
 const header=req.headers.authorization||'';
 if(!header.startsWith('Bearer '))return res.status(401).json({error:'Sign in required'});
 const token=header.slice(7);
 const caller=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:'Bearer '+token}}});
 const {data:identity,error:identityError}=await caller.auth.getUser(token);
 if(identityError||!identity.user)return res.status(401).json({error:'Invalid session'});
 const {data:isAdmin,error:roleError}=await caller.rpc('is_platform_admin');
 if(roleError||isAdmin!==true)return res.status(403).json({error:'Platform administrator required'});
 const {userId}=req.body||{};
 if(typeof userId!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userId))return res.status(400).json({error:'Invalid user ID'});
 if(userId===identity.user.id)return res.status(400).json({error:'Use Account settings to change your own password'});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:target,error:lookupError}=await db.auth.admin.getUserById(userId);
 if(lookupError||!target?.user)return res.status(404).json({error:'Account not found'});
 const temporaryPassword='Tt-'+randomBytes(24).toString('base64url');
 const {error:resetError}=await db.auth.admin.updateUserById(userId,{password:temporaryPassword});
 if(resetError)return res.status(500).json({error:'Could not reset password'});
 // Return the password once over the authenticated response. Never log it or store it in the database.
 return res.status(200).json({email:target.user.email,temporaryPassword});
}
