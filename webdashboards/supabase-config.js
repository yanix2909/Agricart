// Supabase Configuration
// Use window variables ONLY to avoid duplicate declaration errors
(function() {
    'use strict';
    
    // Set window variables if not already set
    if (typeof window !== 'undefined') {
        if (!window.SUPABASE_URL) {
            window.SUPABASE_URL = 'https://afkwexvvuxwbpioqnelp.supabase.co';
        }
        if (!window.SUPABASE_ANON_KEY) {
            window.SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFma3dleHZ2dXh3YnBpb3FuZWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5MzA3MjcsImV4cCI6MjA3ODUwNjcyN30.7r5j1xfWdJwiRZZm8AcOIaBp9VaXoD2QWE3WrGYZNyM';
        }
    }
    
    // Initialize Supabase client
    let supabaseClient = null;
    
    // Helper function to get URL and key (avoids const redeclaration)
    function getSupabaseConfig() {
        if (typeof window !== 'undefined') {
            return {
                url: window.SUPABASE_URL || 'https://afkwexvvuxwbpioqnelp.supabase.co',
                key: window.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFma3dleHZ2dXh3YnBpb3FuZWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5MzA3MjcsImV4cCI6MjA3ODUwNjcyN30.7r5j1xfWdJwiRZZm8AcOIaBp9VaXoD2QWE3WrGYZNyM'
            };
        }
        return {
            url: 'https://afkwexvvuxwbpioqnelp.supabase.co',
            key: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFma3dleHZ2dXh3YnBpb3FuZWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5MzA3MjcsImV4cCI6MjA3ODUwNjcyN30.7r5j1xfWdJwiRZZm8AcOIaBp9VaXoD2QWE3WrGYZNyM'
        };
    }
    
    function initSupabaseClient() {
        // Return existing client if already initialized
        if (supabaseClient) {
            return supabaseClient;
        }
        
        // Use global client if already initialized in HTML
        if (typeof window !== 'undefined' && window.supabaseClient) {
            supabaseClient = window.supabaseClient;
            return supabaseClient;
        }
        
        // Create new client if supabase is available
        if (typeof supabase !== 'undefined') {
            try {
                const config = getSupabaseConfig();
                supabaseClient = supabase.createClient(config.url, config.key);
                if (typeof window !== 'undefined') {
                    window.supabaseClient = supabaseClient;
                }
                console.log('✅ Supabase client initialized');
                return supabaseClient;
            } catch (error) {
                console.error('❌ Error initializing Supabase client:', error);
                throw new Error('Failed to initialize Supabase client: ' + error.message);
            }
        } else {
            throw new Error('Supabase SDK not loaded. Please include the Supabase script tag.');
        }
    }
    
    // Get Supabase client (initializes if needed)
    function getSupabaseClient() {
        if (!supabaseClient) {
            return initSupabaseClient();
        }
        return supabaseClient;
    }
    
    // Export configuration and functions to window
    if (typeof window !== 'undefined') {
        window.initSupabaseClient = initSupabaseClient;
        window.getSupabaseClient = getSupabaseClient;
    }
})();
