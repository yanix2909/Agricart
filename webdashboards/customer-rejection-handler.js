// Customer Rejection/Removal Handler with Email Notifications
// This handles customer rejection/removal with proper auth cleanup and email notifications

class CustomerRejectionHandler {
    constructor() {
        this.supabase = null;
    }

    initialize() {
        // Get Supabase client
        if (typeof window.getSupabaseClient === 'function') {
            this.supabase = window.getSupabaseClient();
        } else if (window.supabaseClient) {
            this.supabase = window.supabaseClient;
        }

        if (!this.supabase) {
            console.error('Supabase client not available');
            return false;
        }

        console.log('Customer Rejection Handler initialized');
        return true;
    }

    /**
     * Reject a customer account
     * - Marks account as rejected
     * - Deletes Supabase auth user via Edge Function (email can be reused)
     * - Queues and sends email notification
     * - Then deletes the customer record (cleanup + email/username reuse)
     */
    async rejectCustomer(customerUid, rejectionReason, staffInfo) {
        try {
            if (!this.initialize()) {
                throw new Error('Supabase client not initialized');
            }

            console.log('Rejecting customer:', customerUid);

            // Call the SQL function
            const { data, error } = await this.supabase.rpc('reject_customer_account', {
                p_customer_uid: customerUid,
                p_rejection_reason: rejectionReason || 'Your account verification was not approved.',
                p_rejected_by: staffInfo.uid || null,
                p_rejected_by_name: staffInfo.name || 'AgriCart Staff',
                p_rejected_by_role: staffInfo.role || 'Staff'
            });

            if (error) {
                throw error;
            }

            console.log('✅ Customer rejected successfully');
            console.log('📧 Email notification queued');

            // Process pending notifications (this will send the rejection email)
            await this.processPendingNotifications();

            // After email has been processed, delete the customer row
            // so the rejected account no longer appears in customer lists.
            try {
                const { error: deleteError } = await this.supabase
                    .from('customers')
                    .delete()
                    .eq('uid', customerUid);

                if (deleteError) {
                    console.warn('⚠️ Failed to delete customer row after rejection:', deleteError);
                } else {
                    console.log('✅ Customer row deleted after rejection');
                }
            } catch (deleteErr) {
                console.warn('⚠️ Error deleting customer row after rejection:', deleteErr);
            }

            // Also delete the Supabase Auth user via Edge Function
            // This ensures the email can be reused for future registrations
            try {
                const { data: authDeleteData, error: authDeleteError } =
                    await this.supabase.functions.invoke('delete-auth-users', {
                        body: { uid: customerUid }
                    });

                if (authDeleteError) {
                    console.warn('⚠️ Failed to delete auth user during rejection (email may remain reserved):', authDeleteError);
                } else {
                    console.log('✅ Auth user deleted via Edge Function on rejection:', authDeleteData);
                }
            } catch (authErr) {
                console.warn('⚠️ Error calling delete-auth-users Edge Function during rejection:', authErr);
            }

            return {
                success: true,
                message: 'Customer account rejected successfully. Notification email will be sent.'
            };

        } catch (error) {
            console.error('Error rejecting customer:', error);
            throw error;
        }
    }

    /**
     * Remove a customer account permanently
     * - Deletes customer record
     * - Deletes Supabase auth user via Edge Function (email can be reused)
     */
    async removeCustomer(customerUid, removalReason, staffInfo) {
        try {
            if (!this.initialize()) {
                throw new Error('Supabase client not initialized');
            }

            console.log('Removing customer:', customerUid);

            // Delete from customer table and log removal in audit trail (handled by SQL function)
            const { data, error } = await this.supabase.rpc('remove_customer_account', {
                p_customer_uid: customerUid,
                p_removal_reason: removalReason || 'Your account has been removed.',
                p_removed_by: staffInfo.uid || null,
                p_removed_by_name: staffInfo.name || 'AgriCart Staff',
                p_removed_by_role: staffInfo.role || 'Staff'
            });

            if (error) {
                throw error;
            }

            console.log('✅ Customer removed successfully from database');

            // Delete Supabase Auth user via Edge Function so email can be reused
            try {
                const { data: authDeleteData, error: authDeleteError } =
                    await this.supabase.functions.invoke('delete-auth-users', {
                        body: { uid: customerUid }
                    });

                if (authDeleteError) {
                    console.warn('⚠️ Failed to delete auth user during removal (email may remain reserved):', authDeleteError);
                } else {
                    console.log('✅ Auth user deleted via Edge Function on removal:', authDeleteData);
                }
            } catch (authErr) {
                console.warn('⚠️ Error calling delete-auth-users Edge Function during removal:', authErr);
            }

            return {
                success: true,
                message: 'Customer account removed successfully!'
            };

        } catch (error) {
            console.error('Error removing customer:', error);
            throw error;
        }
    }

    /**
     * Process pending email notifications
     * Sends emails for rejected/removed customers
     */
    async processPendingNotifications() {
        try {
            // Get pending rejection notifications
            const { data: rejectionNotifs, error: rejError } = await this.supabase
                .rpc('get_pending_rejection_notifications');

            if (rejError) {
                console.error('Error fetching rejection notifications:', rejError);
            } else if (rejectionNotifs && rejectionNotifs.length > 0) {
                console.log(`📧 Processing ${rejectionNotifs.length} rejection notifications`);
                for (const notif of rejectionNotifs) {
                    await this.sendRejectionEmail(notif);
                }
            }

            // Get pending removal notifications
            const { data: removalNotifs, error: remError } = await this.supabase
                .rpc('get_pending_removal_notifications');

            if (remError) {
                console.error('Error fetching removal notifications:', remError);
            } else if (removalNotifs && removalNotifs.length > 0) {
                console.log(`📧 Processing ${removalNotifs.length} removal notifications`);
                for (const notif of removalNotifs) {
                    await this.sendRemovalEmail(notif);
                }
            }

        } catch (error) {
            console.error('Error processing notifications:', error);
        }
    }

    /**
     * Send rejection email notification
     */
    async sendRejectionEmail(notification) {
        try {
            console.log('Sending rejection email to:', notification.customer_email);

            // Prepare email content
            const emailSubject = 'AgriCart Account Status - Verification Not Approved';
            const emailBody = this.generateRejectionEmailHTML(notification);

            // Send via Supabase Edge Function or your email service
            // Option 1: Use Supabase Edge Function
            const { data, error } = await this.supabase.functions.invoke('send-email', {
                body: {
                    to: notification.customer_email,
                    subject: emailSubject,
                    html: emailBody
                }
            });

            if (error) {
                throw error;
            }

            // Mark as sent
            await this.supabase.rpc('mark_rejection_notification_sent', {
                p_notification_id: notification.id
            });

            console.log('✅ Rejection email sent to:', notification.customer_email);

        } catch (error) {
            console.error('Error sending rejection email:', error);
            // Don't throw - continue with other notifications
        }
    }

    /**
     * Send removal email notification
     */
    async sendRemovalEmail(notification) {
        try {
            console.log('Sending removal email to:', notification.customer_email);

            // Prepare email content
            const emailSubject = 'AgriCart Account Removed';
            const emailBody = this.generateRemovalEmailHTML(notification);

            // Send via Supabase Edge Function or your email service
            const { data, error } = await this.supabase.functions.invoke('send-email', {
                body: {
                    to: notification.customer_email,
                    subject: emailSubject,
                    html: emailBody
                }
            });

            if (error) {
                throw error;
            }

            // Mark as sent
            await this.supabase.rpc('mark_removal_notification_sent', {
                p_notification_id: notification.id
            });

            console.log('✅ Removal email sent to:', notification.customer_email);

        } catch (error) {
            console.error('Error sending removal email:', error);
            // Don't throw - continue with other notifications
        }
    }

    /**
     * Generate rejection email HTML
     */
    generateRejectionEmailHTML(notification) {
        return `
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #FFF8E1;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #FFF8E1; padding: 40px 20px;">
        <tr>
            <td align="center">
                <table width="600" cellpadding="0" cellspacing="0" style="background-color: #FFFEF9; border-radius: 16px; box-shadow: 0 4px 20px rgba(49,94,38,0.15); overflow: hidden; border: 2px solid #FFF3C4;">
                    
                    <!-- Header -->
                    <tr>
                        <td style="background: linear-gradient(135deg, #315E26 0%, #4A7C3A 100%); padding: 50px 30px; text-align: center;">
                            <div style="background-color: #FFFEF9; width: 80px; height: 80px; margin: 0 auto 20px; border-radius: 50%; display: flex; align-items: center; justify-content: center; box-shadow: 0 4px 12px rgba(0,0,0,0.2);">
                                <span style="font-size: 48px;">🌾</span>
                            </div>
                            <h1 style="color: #FFFEF9; margin: 0; font-size: 32px; font-weight: 700;">AgriCart</h1>
                            <p style="color: #FFF8E1; margin: 12px 0 0 0; font-size: 15px;">Fresh from Farm to Your Table</p>
                        </td>
                    </tr>
                    
                    <!-- Main Content -->
                    <tr>
                        <td style="padding: 45px 35px;">
                            <h2 style="color: #315E26; margin: 0 0 20px 0; font-size: 26px; font-weight: 700; text-align: center;">
                                Account Verification Status
                            </h2>
                            
                            <p style="color: #2d2d2d; font-size: 16px; line-height: 1.7; margin: 0 0 20px 0;">
                                Dear ${notification.customer_name || 'Customer'},
                            </p>
                            
                            <p style="color: #2d2d2d; font-size: 16px; line-height: 1.7; margin: 0 0 20px 0;">
                                We regret to inform you that your AgriCart account verification was not approved by our team.
                            </p>
                            
                            ${notification.rejection_reason ? `
                            <div style="background-color: #FFF3C4; padding: 20px; border-left: 5px solid #FF9800; border-radius: 8px; margin: 32px 0;">
                                <p style="color: #315E26; font-size: 14px; line-height: 1.6; margin: 0; font-weight: 600;">
                                    📋 Reason:
                                </p>
                                <p style="color: #2d2d2d; font-size: 14px; line-height: 1.6; margin: 8px 0 0 0;">
                                    ${notification.rejection_reason}
                                </p>
                            </div>
                            ` : ''}
                            
                            <p style="color: #2d2d2d; font-size: 16px; line-height: 1.7; margin: 20px 0;">
                                If you believe this was a mistake or would like to reapply, please contact our support team.
                            </p>
                            
                            <p style="color: #666666; font-size: 14px; line-height: 1.6; margin: 20px 0 0 0;">
                                Reviewed by: <strong>${notification.rejected_by_name}</strong> (${notification.rejected_by_role})
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Footer -->
                    <tr>
                        <td style="background-color: #F5E6D3; padding: 32px 35px; border-top: 3px solid #315E26;">
                            <h4 style="color: #315E26; font-size: 16px; margin: 0 0 16px 0; font-weight: 700; text-align: center;">
                                📞 Need Help?
                            </h4>
                            <table width="100%" cellpadding="0" cellspacing="0">
                                <tr>
                                    <td width="50%" style="padding: 8px; text-align: center;">
                                        <div style="background-color: #FFFEF9; padding: 15px; border-radius: 10px; border: 2px solid #315E26;">
                                            <p style="margin: 0 0 6px 0; font-size: 13px; color: #666666; font-weight: 600;">📧 Email</p>
                                            <a href="mailto:calcoacoop@gmail.com" style="color: #315E26; text-decoration: none; font-size: 14px; font-weight: 700;">calcoacoop@gmail.com</a>
                                        </div>
                                    </td>
                                    <td width="50%" style="padding: 8px; text-align: center;">
                                        <div style="background-color: #FFFEF9; padding: 15px; border-radius: 10px; border: 2px solid #315E26;">
                                            <p style="margin: 0 0 6px 0; font-size: 13px; color: #666666; font-weight: 600;">📱 Phone</p>
                                            <a href="tel:+631234567890" style="color: #315E26; text-decoration: none; font-size: 14px; font-weight: 700;">+63 123 456 7890</a>
                                        </div>
                                    </td>
                                </tr>
                            </table>
                            <p style="color: #666666; font-size: 13px; margin: 20px 0 0 0; text-align: center;">
                                © 2024 AgriCart. All rights reserved.<br>
                                🌾 Supporting local agriculture, one order at a time.
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
        `;
    }

    /**
     * Generate removal email HTML
     */
    generateRemovalEmailHTML(notification) {
        return `
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #FFF8E1;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #FFF8E1; padding: 40px 20px;">
        <tr>
            <td align="center">
                <table width="600" cellpadding="0" cellspacing="0" style="background-color: #FFFEF9; border-radius: 16px; box-shadow: 0 4px 20px rgba(49,94,38,0.15); overflow: hidden; border: 2px solid #FFF3C4;">
                    
                    <!-- Header -->
                    <tr>
                        <td style="background: linear-gradient(135deg, #315E26 0%, #4A7C3A 100%); padding: 50px 30px; text-align: center;">
                            <div style="background-color: #FFFEF9; width: 80px; height: 80px; margin: 0 auto 20px; border-radius: 50%; display: flex; align-items: center; justify-content: center; box-shadow: 0 4px 12px rgba(0,0,0,0.2);">
                                <span style="font-size: 48px;">🌾</span>
                            </div>
                            <h1 style="color: #FFFEF9; margin: 0; font-size: 32px; font-weight: 700;">AgriCart</h1>
                            <p style="color: #FFF8E1; margin: 12px 0 0 0; font-size: 15px;">Fresh from Farm to Your Table</p>
                        </td>
                    </tr>
                    
                    <!-- Main Content -->
                    <tr>
                        <td style="padding: 45px 35px;">
                            <h2 style="color: #315E26; margin: 0 0 20px 0; font-size: 26px; font-weight: 700; text-align: center;">
                                Account Removed
                            </h2>
                            
                            <p style="color: #2d2d2d; font-size: 16px; line-height: 1.7; margin: 0 0 20px 0;">
                                Dear ${notification.customer_name || 'Customer'},
                            </p>
                            
                            <p style="color: #2d2d2d; font-size: 16px; line-height: 1.7; margin: 0 0 20px 0;">
                                Your AgriCart account has been removed from our system.
                            </p>
                            
                            ${notification.removal_reason ? `
                            <div style="background-color: #FFF3C4; padding: 20px; border-left: 5px solid #FF9800; border-radius: 8px; margin: 32px 0;">
                                <p style="color: #315E26; font-size: 14px; line-height: 1.6; margin: 0; font-weight: 600;">
                                    📋 Reason:
                                </p>
                                <p style="color: #2d2d2d; font-size: 14px; line-height: 1.6; margin: 8px 0 0 0;">
                                    ${notification.removal_reason}
                                </p>
                            </div>
                            ` : ''}
                            
                            <p style="color: #2d2d2d; font-size: 16px; line-height: 1.7; margin: 20px 0;">
                                If you have any questions or believe this was done in error, please contact our support team.
                            </p>
                            
                            <p style="color: #666666; font-size: 14px; line-height: 1.6; margin: 20px 0 0 0;">
                                Processed by: <strong>${notification.removed_by_name}</strong> (${notification.removed_by_role})
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Footer -->
                    <tr>
                        <td style="background-color: #F5E6D3; padding: 32px 35px; border-top: 3px solid #315E26;">
                            <h4 style="color: #315E26; font-size: 16px; margin: 0 0 16px 0; font-weight: 700; text-align: center;">
                                📞 Contact Support
                            </h4>
                            <table width="100%" cellpadding="0" cellspacing="0">
                                <tr>
                                    <td width="50%" style="padding: 8px; text-align: center;">
                                        <div style="background-color: #FFFEF9; padding: 15px; border-radius: 10px; border: 2px solid #315E26;">
                                            <p style="margin: 0 0 6px 0; font-size: 13px; color: #666666; font-weight: 600;">📧 Email</p>
                                            <a href="mailto:calcoacoop@gmail.com" style="color: #315E26; text-decoration: none; font-size: 14px; font-weight: 700;">calcoacoop@gmail.com</a>
                                        </div>
                                    </td>
                                    <td width="50%" style="padding: 8px; text-align: center;">
                                        <div style="background-color: #FFFEF9; padding: 15px; border-radius: 10px; border: 2px solid #315E26;">
                                            <p style="margin: 0 0 6px 0; font-size: 13px; color: #666666; font-weight: 600;">📱 Phone</p>
                                            <a href="tel:+631234567890" style="color: #315E26; text-decoration: none; font-size: 14px; font-weight: 700;">+63 123 456 7890</a>
                                        </div>
                                    </td>
                                </tr>
                            </table>
                            <p style="color: #666666; font-size: 13px; margin: 20px 0 0 0; text-align: center;">
                                © 2024 AgriCart. All rights reserved.<br>
                                🌾 Supporting local agriculture, one order at a time.
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
        `;
    }
}

// Initialize global instance
window.customerRejectionHandler = new CustomerRejectionHandler();

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    if (window.customerRejectionHandler) {
        window.customerRejectionHandler.initialize();
    }
});

