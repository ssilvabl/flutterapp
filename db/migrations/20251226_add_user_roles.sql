-- Add role column to profiles table
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'free';

-- Add email column to profiles table for admin access
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email TEXT;

-- Update existing profiles to have 'free' role if null
UPDATE profiles SET role = 'free' WHERE role IS NULL;

-- Add constraint to ensure only valid roles
ALTER TABLE profiles ADD CONSTRAINT valid_role CHECK (role IN ('admin', 'free', 'premium'));

-- Create index on role for faster queries
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);
