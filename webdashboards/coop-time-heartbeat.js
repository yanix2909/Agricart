// Cooperative desktop time heartbeat writer
// Publishes the local desktop/laptop epoch to Supabase system_data table
// Includes resilience: IndexedDB queue, localStorage fallback, retry logic, and connection monitoring
// AUTHORITATIVE SOURCE: Web dashboard heartbeat is the primary time source for the entire system
(function(){
    const HEARTBEAT_INTERVAL_MS = 15 * 1000; // 15s
    const MAX_RETRIES = 3;
    const RETRY_DELAY_MS = 5000; // 5 seconds between retries
    const STORAGE_KEY = 'coopTime_heartbeat_fallback';
    const STORAGE_EXPIRY_MS = 10 * 60 * 1000; // 10 minutes expiry for fallback data (extended for resilience)
    const QUEUE_DB_NAME = 'coopTime_heartbeat_queue';
    const QUEUE_STORE_NAME = 'heartbeats';
    const MAX_QUEUE_SIZE = 100; // Maximum heartbeats to queue when offline
    
    let intervalId = null;
    let consecutiveFailures = 0;
    let lastSuccessfulPublish = null;
    let retryTimeoutId = null;
    let db = null;
    let isSyncingQueue = false;

    // Initialize IndexedDB for heartbeat queue
    async function initIndexedDB() {
        if (db) return db;
        
        return new Promise((resolve, reject) => {
            if (!window.indexedDB) {
                console.warn('[coop-time] IndexedDB not available, using localStorage only');
                resolve(null);
                return;
            }
            
            const request = indexedDB.open(QUEUE_DB_NAME, 1);
            
            request.onerror = () => {
                console.warn('[coop-time] Failed to open IndexedDB:', request.error);
                resolve(null);
            };
            
            request.onsuccess = () => {
                db = request.result;
                resolve(db);
            };
            
            request.onupgradeneeded = (event) => {
                const database = event.target.result;
                if (!database.objectStoreNames.contains(QUEUE_STORE_NAME)) {
                    const store = database.createObjectStore(QUEUE_STORE_NAME, { keyPath: 'timestamp', autoIncrement: false });
                    store.createIndex('timestamp', 'timestamp', { unique: true });
                }
            };
        });
    }

    // Store heartbeat data in localStorage as fallback (authoritative web dashboard time)
    function storeFallbackHeartbeat(data) {
        try {
            const fallbackData = {
                ...data,
                storedAt: Date.now(),
                source: 'staff-admin-desktop', // Mark as authoritative web dashboard source
                isAuthoritative: true // Flag to indicate this is the authoritative source
            };
            localStorage.setItem(STORAGE_KEY, JSON.stringify(fallbackData));
        } catch (e) {
            console.warn('[coop-time] Failed to store fallback heartbeat:', e);
        }
    }

    // Queue heartbeat in IndexedDB when Supabase is down
    async function queueHeartbeat(data) {
        try {
            if (!db) {
                await initIndexedDB();
            }
            
            if (!db) {
                // IndexedDB not available, fall back to localStorage
                storeFallbackHeartbeat(data);
                return;
            }
            
            const heartbeat = {
                timestamp: data.epoch_ms,
                epoch_ms: data.epoch_ms,
                iso: data.iso,
                weekday: data.weekday,
                source: 'staff-admin-desktop',
                isAuthoritative: true,
                queuedAt: Date.now()
            };
            
            const transaction = db.transaction([QUEUE_STORE_NAME], 'readwrite');
            const store = transaction.objectStore(QUEUE_STORE_NAME);
            
            // Check queue size and remove oldest if needed
            const countRequest = store.count();
            countRequest.onsuccess = () => {
                if (countRequest.result >= MAX_QUEUE_SIZE) {
                    // Remove oldest entries
                    const index = store.index('timestamp');
                    const cursorRequest = index.openCursor();
                    cursorRequest.onsuccess = (e) => {
                        const cursor = e.target.result;
                        if (cursor) {
                            cursor.delete();
                            cursor.continue();
                        }
                    };
                }
                
                // Add new heartbeat
                store.put(heartbeat);
            };
            
            // Also store in localStorage as immediate fallback
            storeFallbackHeartbeat(data);
            
        } catch (e) {
            console.warn('[coop-time] Failed to queue heartbeat:', e);
            // Fallback to localStorage
            storeFallbackHeartbeat(data);
        }
    }

    // Sync queued heartbeats to Supabase when connection is restored
    async function syncQueuedHeartbeats() {
        if (isSyncingQueue || !db) return;
        
        const supabase = typeof window.getSupabaseClient === 'function' 
            ? window.getSupabaseClient() 
            : (window.supabaseClient || null);
        
        if (!supabase) return;
        
        isSyncingQueue = true;
        
        try {
            const transaction = db.transaction([QUEUE_STORE_NAME], 'readonly');
            const store = transaction.objectStore(QUEUE_STORE_NAME);
            const request = store.getAll();
            
            request.onsuccess = async () => {
                const heartbeats = request.result || [];
                
                if (heartbeats.length === 0) {
                    isSyncingQueue = false;
                    return;
                }
                
                console.log(`[coop-time] Syncing ${heartbeats.length} queued heartbeats to Supabase...`);
                
                // Sort by timestamp (oldest first) and sync the most recent one
                heartbeats.sort((a, b) => b.timestamp - a.timestamp);
                const mostRecent = heartbeats[0];
                
                try {
                    const { error } = await supabase
                        .from('system_data')
                        .upsert({
                            id: 'coopTime',
                            epoch_ms: mostRecent.epoch_ms,
                            iso: mostRecent.iso,
                            weekday: mostRecent.weekday,
                            source: 'staff-admin-desktop',
                            server_ts: mostRecent.epoch_ms,
                            updated_at: mostRecent.epoch_ms
                        }, {
                            onConflict: 'id'
                        });
                    
                    if (!error) {
                        console.log('[coop-time] ✅ Synced queued heartbeat to Supabase');
                        
                        // Clear the queue after successful sync
                        const clearTransaction = db.transaction([QUEUE_STORE_NAME], 'readwrite');
                        const clearStore = clearTransaction.objectStore(QUEUE_STORE_NAME);
                        clearStore.clear();
                        
                        // Update last successful publish
                        lastSuccessfulPublish = mostRecent.epoch_ms;
                        consecutiveFailures = 0;
                    } else {
                        console.warn('[coop-time] Failed to sync queued heartbeat:', error);
                    }
                } catch (e) {
                    console.warn('[coop-time] Error syncing queued heartbeat:', e);
                }
                
                isSyncingQueue = false;
            };
            
            request.onerror = () => {
                console.warn('[coop-time] Failed to read queued heartbeats');
                isSyncingQueue = false;
            };
            
        } catch (e) {
            console.warn('[coop-time] Error syncing queue:', e);
            isSyncingQueue = false;
        }
    }

    // Get fallback heartbeat from localStorage
    function getFallbackHeartbeat() {
        try {
            const stored = localStorage.getItem(STORAGE_KEY);
            if (!stored) return null;
            
            const data = JSON.parse(stored);
            const age = Date.now() - (data.storedAt || 0);
            
            // Only use if less than expiry time
            if (age < STORAGE_EXPIRY_MS) {
                return data;
            }
            
            // Expired, remove it
            localStorage.removeItem(STORAGE_KEY);
            return null;
        } catch (e) {
            console.warn('[coop-time] Failed to read fallback heartbeat:', e);
            return null;
        }
    }

    // Publish heartbeat with retry logic
    // AUTHORITATIVE: This is the primary time source - always publishes, even when Supabase is down
    async function publishToSupabase(retryCount = 0) {
        const now = new Date();
        const nowMs = now.getTime();
        const weekday = ((now.getDay() + 6) % 7) + 1; // Convert to 1=Mon..7=Sun
        
        const heartbeatData = {
            epoch_ms: nowMs,
            iso: now.toISOString(),
            weekday: weekday
        };
        
        try {
            // Get Supabase client
            const supabase = typeof window.getSupabaseClient === 'function' 
                ? window.getSupabaseClient() 
                : (window.supabaseClient || null);
            
            if (!supabase) {
                console.warn('[coop-time] Supabase client not available; queuing heartbeat');
                // Queue heartbeat for later sync - this ensures web dashboard time is preserved
                await queueHeartbeat(heartbeatData);
                return;
            }

            // Upsert to system_data table (id='coopTime')
            // Mark as authoritative web dashboard source
            const { error } = await supabase
                .from('system_data')
                .upsert({
                    id: 'coopTime',
                    epoch_ms: nowMs,
                    iso: now.toISOString(),
                    weekday: weekday,
                    source: 'staff-admin-desktop', // AUTHORITATIVE SOURCE
                    server_ts: nowMs,
                    updated_at: nowMs
                }, {
                    onConflict: 'id'
                });

            if (error) {
                throw error;
            }

            // Success - reset failure counter and store fallback
            consecutiveFailures = 0;
            lastSuccessfulPublish = nowMs;
            
            // Store successful heartbeat as fallback (authoritative)
            storeFallbackHeartbeat(heartbeatData);
            
            // Try to sync any queued heartbeats
            if (consecutiveFailures === 0) {
                syncQueuedHeartbeats();
            }
            
            console.log('[coop-time] ✅ Heartbeat published to Supabase:', nowMs);
            
        } catch (e) {
            consecutiveFailures++;
            console.warn(`[coop-time] ❌ Failed to publish heartbeat (attempt ${retryCount + 1}/${MAX_RETRIES}):`, e);
            
            // CRITICAL: Always queue/store heartbeat even on failure
            // This ensures web dashboard time remains authoritative even when Supabase is down
            await queueHeartbeat(heartbeatData);
            
            // Retry logic with exponential backoff
            if (retryCount < MAX_RETRIES - 1) {
                const delay = RETRY_DELAY_MS * Math.pow(2, retryCount); // Exponential backoff
                console.log(`[coop-time] Retrying in ${delay}ms...`);
                
                retryTimeoutId = setTimeout(() => {
                    publishToSupabase(retryCount + 1);
                }, delay);
            } else {
                console.error('[coop-time] Max retries reached. Heartbeat queued for later sync.');
                // Continue trying periodically even after max retries
                if (consecutiveFailures >= 5) {
                    console.warn('[coop-time] Multiple consecutive failures detected. Heartbeats are being queued.');
                }
            }
        }
    }

    // Monitor connection health
    function checkConnectionHealth() {
        const now = Date.now();
        const timeSinceLastSuccess = lastSuccessfulPublish ? (now - lastSuccessfulPublish) : Infinity;
        
        // If no successful publish in last 2 minutes, only log debug (suppress warning)
        if (timeSinceLastSuccess > 120000) {
            // Suppress warning - only log if really needed (debug level)
            // console.warn('[coop-time] ⚠️ No successful heartbeat in last 2 minutes. Dashboard may be using fallback time.');
            
            // Check if we have fallback data
            const fallback = getFallbackHeartbeat();
            if (fallback) {
                console.debug('[coop-time] Using fallback heartbeat from localStorage:', fallback);
            }
        }
    }

    function startHeartbeat() {
        // Initialize IndexedDB for queue
        initIndexedDB().then(() => {
            // Try to sync any queued heartbeats from previous session
            syncQueuedHeartbeats();
        });
        
        // Publish immediately
        publishToSupabase();
        
        // Then repeat every 15 seconds
        intervalId = setInterval(() => {
            publishToSupabase();
            checkConnectionHealth();
            
            // Periodically try to sync queued heartbeats
            if (consecutiveFailures === 0 && !isSyncingQueue) {
                syncQueuedHeartbeats();
            }
        }, HEARTBEAT_INTERVAL_MS);
        
        // Check health every minute
        setInterval(checkConnectionHealth, 60000);
        
        // Try to sync queue every 30 seconds when connection is restored
        setInterval(() => {
            if (consecutiveFailures === 0 && !isSyncingQueue) {
                syncQueuedHeartbeats();
            }
        }, 30000);
        
        // Stop on page unload
        window.addEventListener('beforeunload', () => {
            if (intervalId) {
                clearInterval(intervalId);
                intervalId = null;
            }
            if (retryTimeoutId) {
                clearTimeout(retryTimeoutId);
                retryTimeoutId = null;
            }
        });
    }

    // Get cooperative time with fallback (for use by other dashboard components)
    async function getCooperativeTime() {
        try {
            const supabase = typeof window.getSupabaseClient === 'function' 
                ? window.getSupabaseClient() 
                : (window.supabaseClient || null);
            
            if (supabase) {
                const { data, error } = await supabase
                    .from('system_data')
                    .select('epoch_ms, iso, weekday, updated_at')
                    .eq('id', 'coopTime')
                    .maybeSingle();
                
                if (!error && data) {
                    return {
                        epochMs: data.epoch_ms,
                        iso: data.iso,
                        weekday: data.weekday,
                        source: 'supabase',
                        updatedAt: data.updated_at
                    };
                }
            }
        } catch (e) {
            console.warn('[coop-time] Error reading from Supabase:', e);
        }
        
        // Fallback to localStorage
        const fallback = getFallbackHeartbeat();
        if (fallback) {
            return {
                epochMs: fallback.epoch_ms,
                iso: fallback.iso,
                weekday: fallback.weekday,
                source: 'localStorage-fallback',
                updatedAt: fallback.storedAt
            };
        }
        
        // Final fallback: use current device time
        const now = new Date();
        return {
            epochMs: now.getTime(),
            iso: now.toISOString(),
            weekday: ((now.getDay() + 6) % 7) + 1,
            source: 'device-time',
            updatedAt: now.getTime()
        };
    }

    // Expose fallback data for other parts of the dashboard
    window.getCoopTimeFallback = function() {
        return getFallbackHeartbeat();
    };

    // Expose connection status
    window.getCoopTimeConnectionStatus = function() {
        return {
            isConnected: consecutiveFailures === 0 && lastSuccessfulPublish !== null,
            consecutiveFailures: consecutiveFailures,
            lastSuccessfulPublish: lastSuccessfulPublish,
            hasFallback: getFallbackHeartbeat() !== null
        };
    };

    // Expose function to get cooperative time (with fallback)
    window.getCooperativeTime = getCooperativeTime;

    // Start when DOM is ready
    if (document.readyState === 'complete' || document.readyState === 'interactive') {
        startHeartbeat();
    } else {
        document.addEventListener('DOMContentLoaded', startHeartbeat);
    }
})();


