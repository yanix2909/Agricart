// Firebase Configuration
const firebaseConfig = {
    apiKey: "AIzaSyAz53g6FvGyQEXaaBVlpCMJ9Hr2QfMvXMU",
    authDomain: "agricart-53501.firebaseapp.com",
    databaseURL: "https://agricart-53501-default-rtdb.firebaseio.com",
    projectId: "agricart-53501",
    storageBucket: "agricart-53501.appspot.com",
    messagingSenderId: "541840919230",
    appId: "1:541840919230:web:d03dc9701f1dbf16092cef",
    measurementId: "G-SZ1P06MCTJ"
};

// Supabase Edge Function URL for FCM notifications
// This uses Supabase Edge Function with Firebase FCM v1 API
const SUPABASE_EDGE_FUNCTION_URL = 'https://afkwexvvuxwbpioqnelp.supabase.co/functions/v1/send-fcm-notification';

// Initialize Firebase
if (typeof firebase !== 'undefined' && typeof firebase.initializeApp === 'function') {
    firebase.initializeApp(firebaseConfig);
}

// Initialize Firebase services (guard for optional SDKs)
const auth = (firebase && typeof firebase.auth === 'function') ? firebase.auth() : null;
const database = (firebase && typeof firebase.database === 'function') ? firebase.database() : null;
const storage = (firebase && typeof firebase.storage === 'function') ? firebase.storage() : null;
const functions = (firebase && typeof firebase.functions === 'function') ? firebase.functions() : null;

// Database references
const dbRefs = {
    users: database.ref('users'),
    staff: database.ref('staff'),
    admins: database.ref('admins'),
    customers: database.ref('customers'),
    farmers: database.ref('farmers'),
    riders: database.ref('riders'),
    products: database.ref('products'),
    orders: database.ref('orders'),
    delivery_orders: database.ref('delivery_orders'), // Structure: { orderId: { proofDeliveryImages: [url1, url2, ...], ...otherFields } }
    inventory: database.ref('inventory'),
    verifications: database.ref('verifications'),
    rejected: database.ref('rejected'),
    sales: database.ref('sales'),
    systemData: database.ref('systemData')
};

/**
 * Delivery Orders Schema Reference:
 * delivery_orders/{orderId}:
 *   - delivery_proof: null | Array<string> - Proof of delivery images (null = no proof yet, array = image URLs)
 *   - proofDeliveryImages: Array<string> - Array of image URLs for proof of delivery images uploaded by riders (legacy field)
 *   - Other fields as needed by the delivery system
 */

// Utility functions for Firebase operations

// Ensure a Firebase Auth session exists for web dashboards
// Many rules and callable functions expect auth != null
if (auth) {
    try {
        if (!auth.currentUser) {
            auth.signInAnonymously().catch(function(err){
                // If anonymous auth is disabled, writes that require auth will still fail
                // Admin email/password flow will override this when used
                console.warn('Anonymous auth not available or failed:', err && err.message);
            });
        }
    } catch (e) {
        console.warn('Failed to establish anonymous auth session:', e && e.message);
    }
}
// Supabase Configuration
const SUPABASE_URL = 'https://afkwexvvuxwbpioqnelp.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFma3dleHZ2dXh3YnBpb3FuZWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5MzA3MjcsImV4cCI6MjA3ODUwNjcyN30.7r5j1xfWdJwiRZZm8AcOIaBp9VaXoD2QWE3WrGYZNyM';

// Initialize Supabase client (use global client if available, otherwise create one)
function initSupabaseClient() {
    // Use global client if already initialized in HTML
    if (typeof window !== 'undefined' && window.supabaseClient) {
        return window.supabaseClient;
    }
    
    // Otherwise, try to create one if supabase is available
    if (typeof supabase !== 'undefined') {
        try {
            const client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
            if (typeof window !== 'undefined') {
                window.supabaseClient = client;
            }
            console.log('✅ Supabase client initialized');
            return client;
        } catch (error) {
            console.error('❌ Error initializing Supabase client:', error);
        }
    }
    return null;
}

const FirebaseUtils = {
    // Get current timestamp
    getTimestamp() {
        return firebase.database.ServerValue.TIMESTAMP;
    },

    // Generate unique ID
    generateId(ref = null) {
        if (ref) {
            return ref.push().key;
        } else {
            // Generate a simple unique ID if no ref provided
            return 'id_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
        }
    },

    // Upload staff ID photo to Supabase Storage (staffid_image bucket)
    async uploadStaffIdPhoto(file, staffId, side, onProgress) {
        if (!file) throw new Error('No file provided');
        const allowedTypes = ['image/jpeg', 'image/png', 'image/jpg'];
        if (!allowedTypes.includes(file.type)) {
            throw new Error('Unsupported file type. Please upload JPG or PNG images.');
        }
        const maxSizeBytes = 5 * 1024 * 1024; // 5MB
        if (file.size > maxSizeBytes) {
            throw new Error('Image too large. Max size is 5MB per file.');
        }

        // Ensure Supabase client is initialized
        const client = initSupabaseClient();
        if (!client) {
            throw new Error('Supabase client not initialized. Please refresh the page.');
        }

        try {
            // Generate unique filename
            const fileExt = file.name.split('.').pop();
            const fileName = `${staffId}_${side}_${Date.now()}.${fileExt}`;
            const filePath = `${staffId}/${fileName}`;

            // Convert file to ArrayBuffer for Supabase
            const arrayBuffer = await file.arrayBuffer();
            
            // Upload to Supabase Storage bucket 'staffid_image'
            if (onProgress) onProgress(50); // Report 50% when starting upload
            
            const { data, error } = await client.storage
                .from('staffid_image')
                .upload(filePath, arrayBuffer, {
                    contentType: file.type,
                    upsert: false
                });

            if (error) {
                console.error('Supabase upload error:', error);
                throw new Error(`Failed to upload ID photo: ${error.message}`);
            }

            if (onProgress) onProgress(100); // Report 100% when done

            // Get public URL
            const { data: urlData } = client.storage
                .from('staffid_image')
                .getPublicUrl(filePath);

            if (!urlData || !urlData.publicUrl) {
                throw new Error('Failed to get image URL from Supabase');
            }

            return urlData.publicUrl;
        } catch (error) {
            console.error('Error uploading staff ID photo to Supabase:', error);
            throw error;
        }
    },

    // Delete all staff ID photos from Supabase Storage (when staff is removed)
    async deleteAllStaffIdPhotos(staffId) {
        try {
            const client = initSupabaseClient();
            if (!client) {
                console.warn('Supabase client not initialized. Cannot delete staff photos.');
                return;
            }

            // List all files in the staffId folder
            const { data: files, error: listError } = await client.storage
                .from('staffid_image')
                .list(staffId, {
                    limit: 100,
                    offset: 0
                });

            if (listError) {
                // Folder might not exist yet, which is fine
                if (listError.message && listError.message.includes('not found')) {
                    return;
                }
                console.warn('Error listing files for deletion:', listError);
                return;
            }

            if (!files || files.length === 0) {
                return; // No files to delete
            }

            // Map all files to their full paths
            const filesToDelete = files.map(file => `${staffId}/${file.name}`);

            // Delete all files
            const { error: deleteError } = await client.storage
                .from('staffid_image')
                .remove(filesToDelete);

            if (deleteError) {
                console.warn('Error deleting staff ID photos:', deleteError);
            } else {
                console.log(`Deleted ${filesToDelete.length} ID photo(s) for staff ${staffId}`);
            }
        } catch (error) {
            console.warn('Error in deleteAllStaffIdPhotos:', error);
            // Don't throw - this is cleanup, shouldn't block the removal
        }
    },

    // Delete old staff ID photos from Supabase Storage
    async deleteOldStaffIdPhotos(staffId, side, keepFileName = null) {
        try {
            const client = initSupabaseClient();
            if (!client) {
                console.warn('Supabase client not initialized. Cannot delete old photos.');
                return;
            }

            // List all files in the staffId folder
            const { data: files, error: listError } = await client.storage
                .from('staffid_image')
                .list(staffId, {
                    limit: 100,
                    offset: 0
                });

            if (listError) {
                // Folder might not exist yet, which is fine
                if (listError.message && listError.message.includes('not found')) {
                    return;
                }
                console.warn('Error listing files for deletion:', listError);
                return;
            }

            if (!files || files.length === 0) {
                return; // No files to delete
            }

            // Filter files by side (front or back) and exclude the keepFileName if provided
            const filesToDelete = files
                .filter(file => {
                    // Check if file matches the side (front or back)
                    const isMatchingSide = side === 'front' 
                        ? file.name.includes('_front_') 
                        : file.name.includes('_back_');
                    
                    if (!isMatchingSide) return false;

                    // If keepFileName is provided, don't delete that file
                    if (keepFileName && file.name === keepFileName) {
                        return false; // Keep this file
                    }

                    return true; // Mark for deletion
                })
                .map(file => `${staffId}/${file.name}`);

            if (filesToDelete.length === 0) {
                return; // No files to delete
            }

            // Delete the old files
            const { error: deleteError } = await client.storage
                .from('staffid_image')
                .remove(filesToDelete);

            if (deleteError) {
                console.warn('Error deleting old staff ID photos:', deleteError);
            } else {
                console.log(`Deleted ${filesToDelete.length} old ${side} ID photo(s) for staff ${staffId}`);
            }
        } catch (error) {
            console.warn('Error in deleteOldStaffIdPhotos:', error);
            // Don't throw - this is cleanup, shouldn't block the update
        }
    },

    // Upload rider ID photo to Supabase Storage (riderid_image bucket)
    async uploadRiderIdPhoto(file, riderId, side, onProgress) {
        if (!file) throw new Error('No file provided');
        const allowedTypes = ['image/jpeg', 'image/png', 'image/jpg'];
        if (!allowedTypes.includes(file.type)) {
            throw new Error('Unsupported file type. Please upload JPG or PNG images.');
        }
        const maxSizeBytes = 5 * 1024 * 1024; // 5MB
        if (file.size > maxSizeBytes) {
            throw new Error('Image too large. Max size is 5MB per file.');
        }

        // Ensure Supabase client is initialized
        const client = initSupabaseClient();
        if (!client) {
            throw new Error('Supabase client not initialized. Please refresh the page.');
        }

        try {
            // Generate unique filename
            const fileExt = file.name.split('.').pop();
            const fileName = `${riderId}_${side}_${Date.now()}.${fileExt}`;
            const filePath = `${riderId}/${fileName}`;

            // Convert file to ArrayBuffer for Supabase
            const arrayBuffer = await file.arrayBuffer();
            
            // Upload to Supabase Storage bucket 'riderid_image'
            if (onProgress) onProgress(50); // Report 50% when starting upload
            
            const { data, error } = await client.storage
                .from('riderid_image')
                .upload(filePath, arrayBuffer, {
                    contentType: file.type,
                    upsert: false
                });

            if (error) {
                console.error('Supabase upload error:', error);
                throw new Error(`Failed to upload ID photo: ${error.message}`);
            }

            if (onProgress) onProgress(100); // Report 100% when done

            // Get public URL
            const { data: urlData } = client.storage
                .from('riderid_image')
                .getPublicUrl(filePath);

            if (!urlData || !urlData.publicUrl) {
                throw new Error('Failed to get image URL from Supabase');
            }

            return urlData.publicUrl;
        } catch (error) {
            console.error('Error uploading rider ID photo to Supabase:', error);
            throw error;
        }
    },

    // Upload farmer ID photo to Supabase Storage (farmerid_image bucket)
    async uploadFarmerIdPhoto(file, farmerId, side, onProgress) {
        if (!file) throw new Error('No file provided');
        const allowedTypes = ['image/jpeg', 'image/png', 'image/jpg'];
        if (!allowedTypes.includes(file.type)) {
            throw new Error('Unsupported file type. Please upload JPG or PNG images.');
        }
        const maxSizeBytes = 5 * 1024 * 1024; // 5MB
        if (file.size > maxSizeBytes) {
            throw new Error('Image too large. Max size is 5MB per file.');
        }

        // Ensure Supabase client is initialized
        const client = initSupabaseClient();
        if (!client) {
            throw new Error('Supabase client not initialized. Please refresh the page.');
        }

        try {
            // Generate unique filename
            const fileExt = file.name.split('.').pop();
            const fileName = `${farmerId}_${side}_${Date.now()}.${fileExt}`;
            const filePath = `${farmerId}/${fileName}`;

            // Convert file to ArrayBuffer for Supabase
            const arrayBuffer = await file.arrayBuffer();
            
            // Upload to Supabase Storage bucket 'farmerid_image'
            if (onProgress) onProgress(50); // Report 50% when starting upload
            
            const { data, error } = await client.storage
                .from('farmerid_image')
                .upload(filePath, arrayBuffer, {
                    contentType: file.type,
                    upsert: false
                });

            if (error) {
                console.error('Supabase upload error:', error);
                throw new Error(`Failed to upload ID photo: ${error.message}`);
            }

            if (onProgress) onProgress(100); // Report 100% when done

            // Get public URL
            const { data: urlData } = client.storage
                .from('farmerid_image')
                .getPublicUrl(filePath);

            if (!urlData || !urlData.publicUrl) {
                throw new Error('Failed to get image URL from Supabase');
            }

            return urlData.publicUrl;
        } catch (error) {
            console.error('Error uploading farmer ID photo to Supabase:', error);
            throw error;
        }
    },

    // Delete all farmer ID photos from Supabase Storage (when farmer is removed)
    async deleteAllFarmerIdPhotos(farmerId) {
        try {
            const client = initSupabaseClient();
            if (!client) {
                console.warn('Supabase client not initialized. Cannot delete farmer photos.');
                return;
            }

            // List all files in the farmerId folder
            const { data: files, error: listError } = await client.storage
                .from('farmerid_image')
                .list(farmerId, {
                    limit: 100,
                    offset: 0
                });

            if (listError) {
                // Folder might not exist yet, which is fine
                if (listError.message && listError.message.includes('not found')) {
                    return;
                }
                console.warn('Error listing files for deletion:', listError);
                return;
            }

            if (!files || files.length === 0) {
                return; // No files to delete
            }

            // Map all files to their full paths
            const filesToDelete = files.map(file => `${farmerId}/${file.name}`);

            // Delete all files
            const { error: deleteError } = await client.storage
                .from('farmerid_image')
                .remove(filesToDelete);

            if (deleteError) {
                console.warn('Error deleting farmer ID photos:', deleteError);
            } else {
                console.log(`Deleted ${filesToDelete.length} ID photo(s) for farmer ${farmerId}`);
            }
        } catch (error) {
            console.warn('Error in deleteAllFarmerIdPhotos:', error);
            // Don't throw - this is cleanup, shouldn't block the removal
        }
    },

    // Delete old farmer ID photos from Supabase Storage
    async deleteOldFarmerIdPhotos(farmerId, side) {
        try {
            const client = initSupabaseClient();
            if (!client) {
                console.warn('Supabase client not initialized. Cannot delete old photos.');
                return;
            }

            // List all files in the farmerId folder
            const { data: files, error: listError } = await client.storage
                .from('farmerid_image')
                .list(farmerId, {
                    limit: 100,
                    offset: 0
                });

            if (listError) {
                // Folder might not exist yet, which is fine
                if (listError.message && listError.message.includes('not found')) {
                    return;
                }
                console.warn('Error listing files for deletion:', listError);
                return;
            }

            if (!files || files.length === 0) {
                return; // No files to delete
            }

            // Filter files by side (front or back)
            const filesToDelete = files
                .filter(file => {
                    // Check if file matches the side (front or back)
                    const isMatchingSide = side === 'front' 
                        ? file.name.includes('_front_') 
                        : file.name.includes('_back_');
                    
                    return isMatchingSide;
                })
                .map(file => `${farmerId}/${file.name}`);

            if (filesToDelete.length === 0) {
                return; // No files to delete
            }

            // Delete the old files
            const { error: deleteError } = await client.storage
                .from('farmerid_image')
                .remove(filesToDelete);

            if (deleteError) {
                console.warn('Error deleting old farmer ID photos:', deleteError);
            } else {
                console.log(`Deleted ${filesToDelete.length} old ${side} ID photo(s) for farmer ${farmerId}`);
            }
        } catch (error) {
            console.warn('Error in deleteOldFarmerIdPhotos:', error);
            // Don't throw - this is cleanup, shouldn't block the update
        }
    },

    // Delete all rider ID photos from Supabase Storage (when rider is removed)
    async deleteAllRiderIdPhotos(riderId) {
        try {
            const client = initSupabaseClient();
            if (!client) {
                console.warn('Supabase client not initialized. Cannot delete rider photos.');
                return;
            }

            // List all files in the riderId folder
            const { data: files, error: listError } = await client.storage
                .from('riderid_image')
                .list(riderId, {
                    limit: 100,
                    offset: 0
                });

            if (listError) {
                // Folder might not exist yet, which is fine
                if (listError.message && listError.message.includes('not found')) {
                    return;
                }
                console.warn('Error listing files for deletion:', listError);
                return;
            }

            if (!files || files.length === 0) {
                return; // No files to delete
            }

            // Map all files to their full paths
            const filesToDelete = files.map(file => `${riderId}/${file.name}`);

            // Delete all files
            const { error: deleteError } = await client.storage
                .from('riderid_image')
                .remove(filesToDelete);

            if (deleteError) {
                console.warn('Error deleting rider ID photos:', deleteError);
            } else {
                console.log(`Deleted ${filesToDelete.length} ID photo(s) for rider ${riderId}`);
            }
        } catch (error) {
            console.warn('Error in deleteAllRiderIdPhotos:', error);
            // Don't throw - this is cleanup, shouldn't block the removal
        }
    },

    // Delete old rider ID photos from Supabase Storage
    async deleteOldRiderIdPhotos(riderId, side) {
        try {
            const client = initSupabaseClient();
            if (!client) {
                console.warn('Supabase client not initialized. Cannot delete old photos.');
                return;
            }

            // List all files in the riderId folder
            const { data: files, error: listError } = await client.storage
                .from('riderid_image')
                .list(riderId, {
                    limit: 100,
                    offset: 0
                });

            if (listError) {
                // Folder might not exist yet, which is fine
                if (listError.message && listError.message.includes('not found')) {
                    return;
                }
                console.warn('Error listing files for deletion:', listError);
                return;
            }

            if (!files || files.length === 0) {
                return; // No files to delete
            }

            // Filter files by side (front or back)
            const filesToDelete = files
                .filter(file => {
                    // Check if file matches the side (front or back)
                    const isMatchingSide = side === 'front' 
                        ? file.name.includes('_front_') 
                        : file.name.includes('_back_');
                    
                    return isMatchingSide;
                })
                .map(file => `${riderId}/${file.name}`);

            if (filesToDelete.length === 0) {
                return; // No files to delete
            }

            // Delete the old files
            const { error: deleteError } = await client.storage
                .from('riderid_image')
                .remove(filesToDelete);

            if (deleteError) {
                console.warn('Error deleting old rider ID photos:', deleteError);
            } else {
                console.log(`Deleted ${filesToDelete.length} old ${side} ID photo(s) for rider ${riderId}`);
            }
        } catch (error) {
            console.warn('Error in deleteOldRiderIdPhotos:', error);
            // Don't throw - this is cleanup, shouldn't block the update
        }
    },

    // Upload file to Supabase Storage (product_image bucket)
    async uploadToSupabase(file, productId, fileIndex, onProgress) {
        if (!file) throw new Error('No file provided');
        const allowedTypes = ['image/jpeg', 'image/png', 'image/jpg'];
        if (!allowedTypes.includes(file.type)) {
            throw new Error('Unsupported file type. Please upload JPG or PNG images.');
        }
        const maxSizeBytes = 5 * 1024 * 1024; // 5MB
        if (file.size > maxSizeBytes) {
            throw new Error('Image too large. Max size is 5MB per file.');
        }

        // Ensure Supabase client is initialized
        const client = initSupabaseClient();
        if (!client) {
            throw new Error('Supabase client not initialized. Please refresh the page.');
        }

        try {
            // Generate unique filename
            const fileExt = file.name.split('.').pop();
            const fileName = `${productId}_${fileIndex}_${Date.now()}.${fileExt}`;
            const filePath = `${productId}/${fileName}`;

            // Convert file to ArrayBuffer for Supabase
            const arrayBuffer = await file.arrayBuffer();
            
            // Upload to Supabase Storage bucket 'product_image'
            if (onProgress) onProgress(50); // Report 50% when starting upload
            
            const { data, error } = await client.storage
                .from('product_image')
                .upload(filePath, arrayBuffer, {
                    contentType: file.type,
                    upsert: false
                });

            if (error) {
                console.error('Supabase upload error:', error);
                throw new Error(`Failed to upload image: ${error.message}`);
            }

            if (onProgress) onProgress(100); // Report 100% when done

            // Get public URL
            const { data: urlData } = client.storage
                .from('product_image')
                .getPublicUrl(filePath);

            if (!urlData || !urlData.publicUrl) {
                throw new Error('Failed to get image URL from Supabase');
            }

            return urlData.publicUrl;
        } catch (error) {
            console.error('Error uploading to Supabase:', error);
            throw error;
        }
    },

    // Upload video to Supabase Storage (product_video bucket)
    async uploadVideoToSupabase(file, productId, fileIndex, onProgress) {
        if (!file) throw new Error('No file provided');
        const allowedTypes = ['video/mp4', 'video/webm', 'video/ogg', 'video/quicktime'];
        if (!allowedTypes.includes(file.type)) {
            throw new Error('Unsupported file type. Please upload MP4, WebM, OGG, or MOV videos.');
        }

        // Validate video duration (1 minute = 60 seconds max)
        return new Promise((resolve, reject) => {
            const video = document.createElement('video');
            video.preload = 'metadata';
            
            video.onloadedmetadata = async () => {
                window.URL.revokeObjectURL(video.src);
                const duration = video.duration;
                
                if (duration > 60) {
                    reject(new Error('Video duration exceeds 1 minute. Maximum allowed duration is 60 seconds.'));
                    return;
                }

                // Ensure Supabase client is initialized
                const client = initSupabaseClient();
                if (!client) {
                    reject(new Error('Supabase client not initialized. Please refresh the page.'));
                    return;
                }

                try {
                    // Generate unique filename
                    const fileExt = file.name.split('.').pop();
                    const fileName = `${productId}_video_${fileIndex}_${Date.now()}.${fileExt}`;
                    const filePath = `${productId}/${fileName}`;

                    // Convert file to ArrayBuffer for Supabase
                    const arrayBuffer = await file.arrayBuffer();
                    
                    // Upload to Supabase Storage bucket 'product_video'
                    if (onProgress) onProgress(50); // Report 50% when starting upload
                    
                    const { data, error } = await client.storage
                        .from('product_video')
                        .upload(filePath, arrayBuffer, {
                            contentType: file.type,
                            upsert: false
                        });

                    if (error) {
                        console.error('Supabase video upload error:', error);
                        reject(new Error(`Failed to upload video: ${error.message}`));
                        return;
                    }

                    if (onProgress) onProgress(100); // Report 100% when done

                    // Get public URL
                    const { data: urlData } = client.storage
                        .from('product_video')
                        .getPublicUrl(filePath);

                    if (!urlData || !urlData.publicUrl) {
                        reject(new Error('Failed to get video URL from Supabase'));
                        return;
                    }

                    resolve({
                        url: urlData.publicUrl,
                        duration: duration
                    });
                } catch (error) {
                    console.error('Error uploading video to Supabase:', error);
                    reject(error);
                }
            };

            video.onerror = () => {
                window.URL.revokeObjectURL(video.src);
                reject(new Error('Failed to read video metadata. Please ensure the file is a valid video.'));
            };

            video.src = URL.createObjectURL(file);
        });
    },

    // Upload file to storage (validation, metadata, progress callback, timeout) - Legacy Firebase Storage
    async uploadFile(file, path, onProgress, timeoutMs = 180000) {
        if (!file) throw new Error('No file provided');
        const allowedTypes = ['image/jpeg', 'image/png', 'image/jpg'];
        if (!allowedTypes.includes(file.type)) {
            throw new Error('Unsupported file type. Please upload JPG or PNG images.');
        }
        const maxSizeBytes = 5 * 1024 * 1024; // 5MB
        if (file.size > maxSizeBytes) {
            throw new Error('Image too large. Max size is 5MB per file.');
        }

        const metadata = { contentType: file.type, cacheControl: 'public,max-age=31536000' };
        if (!storage || typeof storage.ref !== 'function') {
            throw new Error('Storage SDK not available on this page.');
        }
        const storageRef = storage.ref(path);

        // Promise wrapper with state change for progress and timeout guard
        const uploadPromise = new Promise((resolve, reject) => {
            const task = storageRef.put(file, metadata);
            const timer = setTimeout(() => {
                try { task.cancel(); } catch (_) {}
                reject(new Error('Upload timeout. Please try again.'));
            }, timeoutMs);

            task.on('state_changed', (snapshot) => {
                if (typeof onProgress === 'function') {
                    const pct = (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
                    onProgress(pct);
                }
            }, (error) => {
                clearTimeout(timer);
                console.error('Storage upload error:', error && (error.code || error.message), 'path:', path);
                reject(error);
            }, async () => {
                clearTimeout(timer);
                try {
                    const url = await task.snapshot.ref.getDownloadURL();
                    resolve(url);
                } catch (err) {
                    reject(err);
                }
            });
        });

        return await uploadPromise;
    },

    // Get user role
    async getUserRole(uid) {
        try {
            // Check if admin
            const adminSnapshot = await dbRefs.admins.child(uid).once('value');
            if (adminSnapshot.exists()) {
                return 'admin';
            }

            // Check if staff
            const staffSnapshot = await dbRefs.staff.child(uid).once('value');
            if (staffSnapshot.exists()) {
                return 'staff';
            }

            return null;
        } catch (error) {
            console.error('Error getting user role:', error);
            return null;
        }
    },

    // Create user profile
    async createUserProfile(uid, role, data) {
        const userData = {
            ...data,
            uid,
            role,
            profilePicture: data.profilePicture || null, // Initialize profile picture column
            profilePictureUrl: data.profilePictureUrl || data.profilePicture || null, // Initialize profile picture URL column
            photoURL: data.photoURL || data.profilePicture || null, // Initialize photo URL column (alternative name)
            createdAt: this.getTimestamp(),
            updatedAt: this.getTimestamp(),
            status: role === 'admin' ? 'active' : 'pending'
        };

        const updates = {};
        updates[`users/${uid}`] = userData;
        updates[`${role}s/${uid}`] = userData;

        return database.ref().update(updates);
    },

    // Update user profile
    async updateUserProfile(uid, role, data) {
        const updateData = {
            ...data,
            updatedAt: this.getTimestamp()
        };

        const updates = {};
        updates[`users/${uid}`] = updateData;
        updates[`${role}s/${uid}`] = updateData;

        return database.ref().update(updates);
    },

    // Delete user profile
    async deleteUserProfile(uid, role) {
        const updates = {};
        updates[`users/${uid}`] = null;
        updates[`${role}s/${uid}`] = null;

        return database.ref().update(updates);
    },

    // Get online users
    async getOnlineUsers(role) {
        const snapshot = await dbRefs[role + 's'].orderByChild('isOnline').equalTo(true).once('value');
        return snapshot.val() || {};
    },

    // Set user online status
    setUserOnlineStatus(uid, role, isOnline) {
        const updates = {};
        updates[`users/${uid}/isOnline`] = isOnline;
        updates[`users/${uid}/lastSeen`] = this.getTimestamp();
        updates[`${role}s/${uid}/isOnline`] = isOnline;
        updates[`${role}s/${uid}/lastSeen`] = this.getTimestamp();

        return database.ref().update(updates);
    },

    // Listen for real-time updates
    onDataChange(ref, callback) {
        return ref.on('value', callback);
    },

    // Remove listener
    offDataChange(ref, callback) {
        ref.off('value', callback);
    },

    // Update proof of delivery images for a delivery order
    async updateProofDeliveryImages(orderId, imageUrls) {
        if (!orderId) throw new Error('Order ID is required');
        if (!Array.isArray(imageUrls)) {
            throw new Error('Image URLs must be an array');
        }

        const updates = {
            [`delivery_orders/${orderId}/proofDeliveryImages`]: imageUrls,
            [`delivery_orders/${orderId}/updatedAt`]: this.getTimestamp()
        };

        return database.ref().update(updates);
    },

    // Add proof of delivery image URL to existing array
    async addProofDeliveryImage(orderId, imageUrl) {
        if (!orderId) throw new Error('Order ID is required');
        if (!imageUrl) throw new Error('Image URL is required');

        const orderRef = database.ref(`delivery_orders/${orderId}`);
        const snapshot = await orderRef.once('value');
        const orderData = snapshot.val() || {};

        const existingImages = Array.isArray(orderData.proofDeliveryImages) 
            ? orderData.proofDeliveryImages 
            : [];

        // Avoid duplicates
        if (!existingImages.includes(imageUrl)) {
            existingImages.push(imageUrl);
        }

        const updates = {
            [`delivery_orders/${orderId}/proofDeliveryImages`]: existingImages,
            [`delivery_orders/${orderId}/updatedAt`]: this.getTimestamp()
        };

        return database.ref().update(updates);
    },

    // Get proof of delivery images for an order
    async getProofDeliveryImages(orderId) {
        if (!orderId) throw new Error('Order ID is required');

        const snapshot = await database.ref(`delivery_orders/${orderId}/proofDeliveryImages`).once('value');
        const images = snapshot.val();
        return Array.isArray(images) ? images : [];
    },

    // Migration: Add delivery_proof field to all existing delivery orders
    async migrateDeliveryOrdersAddProofField() {
        console.log('🔄 Starting migration: Adding delivery_proof field to all delivery orders...');
        
        try {
            const snapshot = await database.ref('delivery_orders').once('value');
            const allOrders = snapshot.val() || {};
            const orderIds = Object.keys(allOrders);
            
            console.log(`📦 Found ${orderIds.length} delivery orders to update`);
            
            if (orderIds.length === 0) {
                console.log('✅ No delivery orders found. Migration complete.');
                return { updated: 0, total: 0 };
            }
            
            const updates = {};
            let updatedCount = 0;
            
            // Prepare updates for all orders
            orderIds.forEach(orderId => {
                const order = allOrders[orderId];
                // Only add delivery_proof if it doesn't already exist
                if (order && order.delivery_proof === undefined) {
                    updates[`delivery_orders/${orderId}/delivery_proof`] = null; // Set to null initially
                    updatedCount++;
                }
            });
            
            if (Object.keys(updates).length === 0) {
                console.log('✅ All delivery orders already have delivery_proof field. Migration complete.');
                return { updated: 0, total: orderIds.length };
            }
            
            // Apply all updates in a single batch
            await database.ref().update(updates);
            
            console.log(`✅ Migration complete! Updated ${updatedCount} delivery orders with delivery_proof field.`);
            return { updated: updatedCount, total: orderIds.length };
            
        } catch (error) {
            console.error('❌ Migration failed:', error);
            throw error;
        }
    },

    // Upload featured media (image or video) to Supabase Storage (featured_display bucket)
    async uploadFeaturedMedia(file, onProgress) {
        if (!file) throw new Error('No file provided');
        
        const fileName = file.name.toLowerCase();
        const isImage = fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') || 
                       fileName.endsWith('.png') || fileName.endsWith('.gif') || 
                       fileName.endsWith('.webp') || fileName.endsWith('.bmp') || 
                       fileName.endsWith('.svg');
        const isVideo = fileName.endsWith('.mp4') || fileName.endsWith('.mov') || 
                       fileName.endsWith('.avi') || fileName.endsWith('.webm') ||
                       fileName.endsWith('.mkv') || fileName.endsWith('.flv') ||
                       fileName.endsWith('.wmv');

        if (!isImage && !isVideo) {
            throw new Error('Unsupported file type. Please upload images (JPG, PNG, GIF, WEBP, BMP, SVG) or videos (MP4, MOV, AVI, WEBM, MKV, FLV, WMV).');
        }

        // Validate image size (10MB max)
        if (isImage && file.size > 10 * 1024 * 1024) {
            throw new Error('Image too large. Max size is 10MB per file.');
        }

        // Validate video size (50MB max) and duration (30 seconds max)
        if (isVideo) {
            if (file.size > 50 * 1024 * 1024) {
                throw new Error('Video too large. Max size is 50MB per file.');
            }

            // Validate video duration
            return new Promise((resolve, reject) => {
                const video = document.createElement('video');
                video.preload = 'metadata';
                
                video.onloadedmetadata = async () => {
                    window.URL.revokeObjectURL(video.src);
                    const duration = video.duration;
                    
                    if (duration > 30) {
                        reject(new Error('Video duration exceeds 30 seconds. Maximum allowed duration is 30 seconds.'));
                        return;
                    }

                    // Ensure Supabase client is initialized
                    const client = initSupabaseClient();
                    if (!client) {
                        reject(new Error('Supabase client not initialized. Please refresh the page.'));
                        return;
                    }

                    try {
                        // Generate unique filename
                        const fileExt = file.name.split('.').pop();
                        const fileName = `featured_${Date.now()}_${Math.random().toString(36).substring(7)}.${fileExt}`;

                        // Convert file to ArrayBuffer for Supabase
                        const arrayBuffer = await file.arrayBuffer();
                        
                        // Upload to Supabase Storage bucket 'featured_display'
                        if (onProgress) onProgress(50);
                        
                        const { data, error } = await client.storage
                            .from('featured_display')
                            .upload(fileName, arrayBuffer, {
                                contentType: file.type,
                                upsert: false
                            });

                        if (error) {
                            console.error('Supabase featured media upload error:', error);
                            reject(new Error(`Failed to upload: ${error.message}`));
                            return;
                        }

                        if (onProgress) onProgress(100);

                        // Get public URL
                        const { data: urlData } = client.storage
                            .from('featured_display')
                            .getPublicUrl(fileName);

                        if (!urlData || !urlData.publicUrl) {
                            reject(new Error('Failed to get media URL from Supabase'));
                            return;
                        }

                        resolve({
                            url: urlData.publicUrl,
                            fileName: fileName,
                            type: isVideo ? 'video' : 'image',
                            duration: isVideo ? duration : null
                        });
                    } catch (error) {
                        console.error('Error uploading featured media to Supabase:', error);
                        reject(error);
                    }
                };

                video.onerror = () => {
                    window.URL.revokeObjectURL(video.src);
                    reject(new Error('Failed to read video metadata. Please ensure the file is a valid video.'));
                };

                video.src = URL.createObjectURL(file);
            });
        }

        // Handle image upload
        const client = initSupabaseClient();
        if (!client) {
            throw new Error('Supabase client not initialized. Please refresh the page.');
        }

        try {
            // Generate unique filename
            const fileExt = file.name.split('.').pop();
            const fileName = `featured_${Date.now()}_${Math.random().toString(36).substring(7)}.${fileExt}`;

            // Convert file to ArrayBuffer for Supabase
            const arrayBuffer = await file.arrayBuffer();
            
            // Upload to Supabase Storage bucket 'featured_display'
            if (onProgress) onProgress(50);
            
            const { data, error } = await client.storage
                .from('featured_display')
                .upload(fileName, arrayBuffer, {
                    contentType: file.type,
                    upsert: false
                });

            if (error) {
                console.error('Supabase featured media upload error:', error);
                throw new Error(`Failed to upload: ${error.message}`);
            }

            if (onProgress) onProgress(100);

            // Get public URL
            const { data: urlData } = client.storage
                .from('featured_display')
                .getPublicUrl(fileName);

            if (!urlData || !urlData.publicUrl) {
                throw new Error('Failed to get media URL from Supabase');
            }

            return {
                url: urlData.publicUrl,
                fileName: fileName,
                type: 'image',
                duration: null
            };
        } catch (error) {
            console.error('Error uploading featured media to Supabase:', error);
            throw error;
        }
    },

    // Delete featured media from Supabase Storage
    async deleteFeaturedMedia(fileName) {
        const client = initSupabaseClient();
        if (!client) {
            throw new Error('Supabase client not initialized. Please refresh the page.');
        }

        try {
            const { error } = await client.storage
                .from('featured_display')
                .remove([fileName]);

            if (error) {
                console.error('Supabase delete error:', error);
                throw new Error(`Failed to delete: ${error.message}`);
            }

            return true;
        } catch (error) {
            console.error('Error deleting featured media:', error);
            throw error;
        }
    },

    // List all featured media files
    async listFeaturedMedia() {
        const client = initSupabaseClient();
        if (!client) {
            throw new Error('Supabase client not initialized. Please refresh the page.');
        }

        try {
            const { data: files, error } = await client.storage
                .from('featured_display')
                .list();

            if (error) {
                console.error('Supabase list error:', error);
                throw new Error(`Failed to list files: ${error.message}`);
            }

            return files || [];
        } catch (error) {
            console.error('Error listing featured media:', error);
            throw error;
        }
    }
};

// Initialize presence system for online/offline status
const initializePresenceSystem = (uid, role) => {
    if (!uid || !role) return;

    const userRef = database.ref(`users/${uid}`);
    const userRoleRef = database.ref(`${role}s/${uid}`);
    
    // Set up presence
    const isOnlineForDatabase = {
        isOnline: true,
        lastSeen: firebase.database.ServerValue.TIMESTAMP
    };

    const isOfflineForDatabase = {
        isOnline: false,
        lastSeen: firebase.database.ServerValue.TIMESTAMP
    };

    // Create a reference to the special '.info/connected' path
    const connectedRef = database.ref('.info/connected');
    
    connectedRef.on('value', (snapshot) => {
        if (snapshot.val() === false) {
            return;
        }

        // Set online status
        userRef.update(isOnlineForDatabase);
        userRoleRef.update(isOnlineForDatabase);

        // Set offline status when disconnected
        userRef.onDisconnect().update(isOfflineForDatabase);
        userRoleRef.onDisconnect().update(isOfflineForDatabase);
    });
};

// Error handling utility
const handleFirebaseError = (error) => {
    console.error('Firebase Error:', error);
    
    const errorMessages = {
        'auth/user-not-found': 'User not found. Please check your credentials.',
        'auth/wrong-password': 'Incorrect password. Please try again.',
        'auth/invalid-email': 'Invalid email format.',
        'auth/user-disabled': 'This account has been disabled.',
        'auth/too-many-requests': 'Too many failed attempts. Please try again later.',
        'permission-denied': 'You do not have permission to perform this action.',
        'network-request-failed': 'Network error. Please check your connection.',
        'default': 'An error occurred. Please try again.'
    };

    return errorMessages[error.code] || errorMessages['default'];
};

// Export configuration and utilities
window.firebaseConfig = firebaseConfig;
window.firebaseConfig.SUPABASE_EDGE_FUNCTION_URL = SUPABASE_EDGE_FUNCTION_URL; // Expose Supabase Edge Function URL
window.firebaseConfig.SUPABASE_ANON_KEY = SUPABASE_ANON_KEY; // Expose Supabase Anon Key for Edge Function auth
window.FirebaseUtils = FirebaseUtils;
window.dbRefs = dbRefs;
window.handleFirebaseError = handleFirebaseError;
window.initializePresenceSystem = initializePresenceSystem;
window.functions = functions;

// Expose migration function globally for manual execution if needed
window.migrateDeliveryProof = async function() {
    if (window.FirebaseUtils && typeof window.FirebaseUtils.migrateDeliveryOrdersAddProofField === 'function') {
        try {
            const result = await window.FirebaseUtils.migrateDeliveryOrdersAddProofField();
            alert(`Migration complete!\n\nUpdated: ${result.updated} orders\nTotal: ${result.total} orders`);
            return result;
        } catch (error) {
            alert('Migration failed: ' + error.message);
            throw error;
        }
    } else {
        alert('Migration function not available. Please refresh the page.');
    }
};
