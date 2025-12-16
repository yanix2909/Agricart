// Firebase Cloud Functions for Admin Operations
// This file contains server-side functions that can delete Firebase Auth accounts with admin privileges

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
admin.initializeApp();

// Cloud Function to delete a user account with admin privileges
exports.deleteUserAccount = functions.https.onCall(async (data, context) => {
    try {
        // Verify that the caller is authenticated and has admin/staff privileges
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
        }

        const { uid, userRole } = data;
        
        if (!uid) {
            throw new functions.https.HttpsError('invalid-argument', 'User ID is required');
        }

        // Check if the caller has admin or staff privileges
        const callerUid = context.auth.uid;
        const callerDoc = await admin.firestore().collection('users').doc(callerUid).get();
        
        if (!callerDoc.exists) {
            throw new functions.https.HttpsError('permission-denied', 'Caller not found in users collection');
        }

        const callerData = callerDoc.data();
        if (callerData.role !== 'admin' && callerData.role !== 'staff') {
            throw new functions.https.HttpsError('permission-denied', 'Only admin and staff can delete user accounts');
        }

        // Delete the Firebase Auth account
        await admin.auth().deleteUser(uid);
        
        console.log(`Successfully deleted Firebase Auth account for user: ${uid}`);
        
        return {
            success: true,
            message: `User account ${uid} deleted successfully`,
            deletedAt: admin.firestore.FieldValue.serverTimestamp()
        };

    } catch (error) {
        console.error('Error deleting user account:', error);
        throw new functions.https.HttpsError('internal', `Failed to delete user account: ${error.message}`);
    }
});

// Cloud Function to delete multiple user accounts
exports.deleteMultipleUserAccounts = functions.https.onCall(async (data, context) => {
    try {
        // Verify that the caller is authenticated and has admin/staff privileges
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
        }

        const { uids } = data;
        
        if (!uids || !Array.isArray(uids) || uids.length === 0) {
            throw new functions.https.HttpsError('invalid-argument', 'Array of user IDs is required');
        }

        // Check if the caller has admin or staff privileges
        const callerUid = context.auth.uid;
        const callerDoc = await admin.firestore().collection('users').doc(callerUid).get();
        
        if (!callerDoc.exists) {
            throw new functions.https.HttpsError('permission-denied', 'Caller not found in users collection');
        }

        const callerData = callerDoc.data();
        if (callerData.role !== 'admin' && callerData.role !== 'staff') {
            throw new functions.https.HttpsError('permission-denied', 'Only admin and staff can delete user accounts');
        }

        const results = [];
        
        // Delete each user account
        for (const uid of uids) {
            try {
                await admin.auth().deleteUser(uid);
                results.push({ uid, success: true, message: 'Deleted successfully' });
                console.log(`Successfully deleted Firebase Auth account for user: ${uid}`);
            } catch (error) {
                results.push({ uid, success: false, error: error.message });
                console.error(`Failed to delete Firebase Auth account for user ${uid}:`, error);
            }
        }
        
        return {
            success: true,
            message: `Processed ${uids.length} user accounts`,
            results: results,
            deletedAt: admin.firestore.FieldValue.serverTimestamp()
        };

    } catch (error) {
        console.error('Error deleting multiple user accounts:', error);
        throw new functions.https.HttpsError('internal', `Failed to delete user accounts: ${error.message}`);
    }
});

// Atomic stock reservation when a new order is created
exports.onOrderCreateReserveStock = functions.database.ref('/orders/{orderId}')
    .onCreate(async (snapshot, context) => {
        const order = snapshot.val();
        if (!order || !Array.isArray(order.items) || order.stockReserved === true) {
            return null;
        }

        const db = admin.database();
        const updates = {};

        // Reserve stock per item using transactions
        for (const item of order.items) {
            if (!item || !item.productId || !item.quantity) continue;
            
            // Get the product to check current availability
            const productRef = db.ref(`products/${item.productId}`);
            const productSnapshot = await productRef.once('value');
            const product = productSnapshot.val();
            
            if (!product) {
                throw new Error(`Product ${item.productId} not found`);
            }
            
            // Calculate available quantity: base - reserved - sold
            const baseQuantity = product.availableQuantity || 0;
            const soldQuantity = product.soldQuantity || 0;
            const currentReserved = product.currentReserved || 0;
            const availableQty = baseQuantity - soldQuantity - currentReserved;
            
            if (availableQty < item.quantity) {
                throw new Error(`Insufficient stock for product ${item.productId}`);
            }
            
            // Update current reserved quantity
            await productRef.update({
                currentReserved: currentReserved + item.quantity
            });


        }

        // All reservations succeeded; mark on the order to prevent double-decrement
        updates[`/orders/${context.params.orderId}/stockReserved`] = true;
        updates[`/orders/${context.params.orderId}/updatedAt`] = admin.database.ServerValue.TIMESTAMP;
        await db.ref().update(updates);
        return null;
    } catch (error) {
        console.error('Error reserving stock:', error);
        // Mark order as failed due to insufficient stock
        await snapshot.ref.update({ 
            status: 'rejected', 
            rejectionReason: `Stock reservation failed: ${error.message}`, 
            stockReserved: false, 
            updatedAt: admin.database.ServerValue.TIMESTAMP 
        });
        return null;
    });

// Restore stock when an order is cancelled or rejected
exports.onOrderUpdateRestoreStock = functions.database.ref('/orders/{orderId}')
    .onUpdate(async (change, context) => {
        const before = change.before.val();
        const after = change.after.val();
        if (!after || !Array.isArray(after.items)) {
            return null;
        }

        const wasReserved = !!after.stockReserved;
        const statusChangedToCancelled = before.status !== after.status && (after.status === 'cancelled' || after.status === 'rejected');
        const alreadyRestored = !!after.stockRestored;

        if (!wasReserved || !statusChangedToCancelled || alreadyRestored) {
            return null;
        }

        const db = admin.database();

        for (const item of after.items) {
            if (!item || !item.productId || !item.quantity) continue;
            const productRef = db.ref(`products/${item.productId}`);
            
            // Get current reserved quantity and reduce it
            const productSnapshot = await productRef.once('value');
            const product = productSnapshot.val();
            if (product) {
                const currentReserved = product.currentReserved || 0;
                const newReserved = Math.max(0, currentReserved - item.quantity);
                
                await productRef.update({
                    currentReserved: newReserved
                });
            }
        }

        await change.after.ref.update({ stockRestored: true, updatedAt: admin.database.ServerValue.TIMESTAMP });
        return null;
    });

// Send FCM when a new customer notification is created
exports.onCustomerNotificationCreate = functions.database
    .ref('/notifications/customers/{customerId}/{notificationId}')
    .onCreate(async (snapshot, context) => {
        try {
            const notification = snapshot.val();
            const { customerId } = context.params;

            if (!notification) {
                return null;
            }

            // Fetch customer's FCM token
            const db = admin.database();
            const tokenSnapshot = await db.ref(`customers/${customerId}/fcmToken`).once('value');
            const token = tokenSnapshot.val();

            if (!token) {
                console.log(`No FCM token for customer ${customerId}, skipping push.`);
                return null;
            }

            // Build FCM payload
            const message = {
                token,
                notification: {
                    title: notification.title || 'AgriCart',
                    body: notification.message || '',
                },
                data: {
                    type: notification.type || 'notification',
                    orderId: notification.orderId ? String(notification.orderId) : '',
                    notificationId: String(notification.id || context.params.notificationId),
                },
                android: {
                    priority: 'high',
                    notification: {
                        channelId: 'agricart_customer_channel',
                    }
                },
                apns: {
                    headers: {
                        'apns-priority': '10'
                    },
                    payload: {
                        aps: {
                            sound: 'default'
                        }
                    }
                }
            };

            await admin.messaging().send(message);
            console.log(`Sent FCM to customer ${customerId} for notification ${context.params.notificationId}`);
            return null;
        } catch (error) {
            console.error('Error sending customer notification FCM:', error);
            return null;
        }
    });

// Send push notifications when order status changes to specific statuses
exports.onOrderStatusChange = functions.database
    .ref('/orders/{orderId}/status')
    .onUpdate(async (change, context) => {
        try {
            const beforeStatus = change.before.val();
            const afterStatus = change.after.val();
            const orderId = context.params.orderId;

            // Only proceed if status actually changed
            if (beforeStatus === afterStatus) {
                return null;
            }

            // Get the full order data
            const orderSnapshot = await change.after.ref.parent.once('value');
            const order = orderSnapshot.val();

            if (!order || !order.customerId) {
                console.log(`Order ${orderId} missing customerId, skipping notification.`);
                return null;
            }

            const customerId = order.customerId;

            // Define notification types for each status
            const statusNotificationMap = {
                'confirmed': {
                    type: 'order_confirmed',
                    title: 'Order Confirmed',
                    message: `Your order #${orderId.substring(0, 8)} has been confirmed!`
                },
                'rejected': {
                    type: 'order_rejected',
                    title: 'Order Rejected',
                    message: `Your order #${orderId.substring(0, 8)} has been rejected.`
                },
                'cancelled': {
                    type: 'order_cancelled',
                    title: 'Order Cancelled',
                    message: `Your order #${orderId.substring(0, 8)} has been cancelled.`
                },
                'cancellation_confirmed': {
                    type: 'order_cancellation_confirmed',
                    title: 'Cancellation Confirmed',
                    message: `Your cancellation request for order #${orderId.substring(0, 8)} has been confirmed.`
                },
                'out_for_delivery': {
                    type: 'order_out_for_delivery',
                    title: 'Order Out for Delivery',
                    message: `Your order #${orderId.substring(0, 8)} is out for delivery!`
                },
                'pickup_ready': {
                    type: 'order_ready_to_pickup',
                    title: 'Order Ready for Pickup',
                    message: `Your order #${orderId.substring(0, 8)} is ready for pickup!`
                },
                'delivered': {
                    type: 'order_delivered',
                    title: 'Order Delivered',
                    message: `Your order #${orderId.substring(0, 8)} has been delivered successfully!`
                },
                // CRITICAL: Disabled 'picked_up' - staff dashboard now creates this notification in Supabase
                // This prevents duplicate notifications when order is marked as picked up
                // 'picked_up': {
                //     type: 'order_successful',
                //     title: 'Order Received',
                //     message: `Your order #${orderId.substring(0, 8)} has been received successfully!`
                // },
                'failed': {
                    type: 'order_failed',
                    title: 'Order Failed',
                    message: `Your order #${orderId.substring(0, 8)} has failed. Please contact support.`
                }
            };

            // Check if this status change should trigger a notification
            const notificationConfig = statusNotificationMap[afterStatus];
            if (!notificationConfig) {
                console.log(`Status ${afterStatus} does not require notification.`);
                return null;
            }

            // Fetch customer's FCM token
            const db = admin.database();
            const tokenSnapshot = await db.ref(`customers/${customerId}/fcmToken`).once('value');
            const token = tokenSnapshot.val();

            if (!token) {
                console.log(`No FCM token for customer ${customerId}, skipping push notification.`);
                // Still create the notification in database for in-app viewing
            }

            // Create notification in Firebase Database
            const notificationId = `order_${orderId}_${afterStatus}_${Date.now()}`;
            const notificationData = {
                id: notificationId,
                title: notificationConfig.title,
                message: notificationConfig.message,
                type: notificationConfig.type,
                timestamp: Date.now(),
                isRead: false,
                orderId: orderId
            };

            // Save notification to database (this will trigger onCustomerNotificationCreate to send FCM)
            await db.ref(`notifications/customers/${customerId}/${notificationId}`).set(notificationData);

            // If we have a token, send FCM directly (backup in case onCustomerNotificationCreate fails)
            if (token) {
                try {
                    const message = {
                        token,
                        notification: {
                            title: notificationConfig.title,
                            body: notificationConfig.message,
                        },
                        data: {
                            type: notificationConfig.type,
                            orderId: orderId,
                            notificationId: notificationId,
                        },
                        android: {
                            priority: 'high',
                            notification: {
                                channelId: 'agricart_customer_channel',
                            }
                        },
                        apns: {
                            headers: {
                                'apns-priority': '10'
                            },
                            payload: {
                                aps: {
                                    sound: 'default'
                                }
                            }
                        }
                    };

                    await admin.messaging().send(message);
                    console.log(`Sent FCM to customer ${customerId} for order ${orderId} status change: ${afterStatus}`);
                } catch (fcmError) {
                    console.error(`Error sending FCM for order status change: ${fcmError}`);
                    // Don't throw - notification is already saved to database
                }
            }

            return null;
        } catch (error) {
            console.error('Error handling order status change notification:', error);
            return null;
        }
    });
