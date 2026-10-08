-- ==============================================================================
-- SCRIBBLE - SUPABASE DATABASE SCHEMA & REALTIME CONFIGURATION
-- Run this in your Supabase Project -> SQL Editor
-- ==============================================================================

-- 1. PROFILES TABLE (Stores user information)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT NOT NULL,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public profiles are viewable by authenticated users" 
ON public.profiles FOR SELECT 
TO authenticated 
USING (true);

CREATE POLICY "Users can insert their own profile" 
ON public.profiles FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile" 
ON public.profiles FOR UPDATE 
TO authenticated 
USING (auth.uid() = id);

-- 2. PAIRING CODES TABLE (Temporary 6-character codes to connect users)
CREATE TABLE IF NOT EXISTS public.pairing_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(6) UNIQUE NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (timezone('utc'::text, now()) + interval '24 hours'),
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.pairing_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Pairing codes viewable by authenticated users" 
ON public.pairing_codes FOR SELECT 
TO authenticated 
USING (true);

CREATE POLICY "Users can create pairing codes" 
ON public.pairing_codes FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their pairing codes" 
ON public.pairing_codes FOR DELETE 
TO authenticated 
USING (auth.uid() = user_id);

-- 3. CONNECTIONS TABLE (Represents paired users)
CREATE TABLE IF NOT EXISTS public.connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_1 UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    user_2 UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT unique_user_pair UNIQUE (user_1, user_2),
    CONSTRAINT different_users CHECK (user_1 <> user_2)
);

ALTER TABLE public.connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view connections they belong to" 
ON public.connections FOR SELECT 
TO authenticated 
USING (auth.uid() = user_1 OR auth.uid() = user_2);

CREATE POLICY "Authenticated users can create connections" 
ON public.connections FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = user_1 OR auth.uid() = user_2);

CREATE POLICY "Users can delete their own connections" 
ON public.connections FOR DELETE 
TO authenticated 
USING (auth.uid() = user_1 OR auth.uid() = user_2);

-- 4. LATEST SCRIBBLES TABLE (One latest scribble per connection)
CREATE TABLE IF NOT EXISTS public.scribbles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID REFERENCES public.connections(id) ON DELETE CASCADE NOT NULL UNIQUE,
    sender_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    image_url TEXT,
    text_content TEXT,
    is_cleared BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.scribbles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Connection members can view scribble" 
ON public.scribbles FOR SELECT 
TO authenticated 
USING (
    EXISTS (
        SELECT 1 FROM public.connections c
        WHERE c.id = connection_id
        AND (c.user_1 = auth.uid() OR c.user_2 = auth.uid())
    )
);

CREATE POLICY "Connection members can insert or replace scribble" 
ON public.scribbles FOR INSERT 
TO authenticated 
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.connections c
        WHERE c.id = connection_id
        AND (c.user_1 = auth.uid() OR c.user_2 = auth.uid())
    )
);

CREATE POLICY "Connection members can update scribble" 
ON public.scribbles FOR UPDATE 
TO authenticated 
USING (
    EXISTS (
        SELECT 1 FROM public.connections c
        WHERE c.id = connection_id
        AND (c.user_1 = auth.uid() OR c.user_2 = auth.uid())
    )
);

-- 5. REALTIME REPLICATION SETUP
-- Add scribbles and connections to Supabase Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.scribbles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.connections;

-- 6. STORAGE BUCKETS (avatars, scribbles)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public) 
VALUES ('scribbles', 'scribbles', true)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: Public read access
CREATE POLICY "Public avatar access" 
ON storage.objects FOR SELECT 
USING (bucket_id = 'avatars');

CREATE POLICY "Authenticated user avatar upload" 
ON storage.objects FOR INSERT 
TO authenticated 
WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "Public scribble image access" 
ON storage.objects FOR SELECT 
USING (bucket_id = 'scribbles');

CREATE POLICY "Authenticated user scribble upload" 
ON storage.objects FOR INSERT 
TO authenticated 
WITH CHECK (bucket_id = 'scribbles');
