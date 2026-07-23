import { createClient } from '@supabase/supabase-js';

export const supabaseUrl =
  import.meta.env.VITE_SUPABASE_URL || 'https://iejbogkqknldxoyepvun.supabase.co';

export const supabasePublishableKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  'sb_publishable_fbgL1lczsWo3sRfsvdO2ZQ_up5cH9CZ';

export const supabase = createClient(supabaseUrl, supabasePublishableKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
  realtime: {
    params: {
      eventsPerSecond: 8,
    },
  },
});

export function publicProjectLabel() {
  try {
    return new URL(supabaseUrl).host.replace('.supabase.co', '');
  } catch {
    return supabaseUrl;
  }
}
