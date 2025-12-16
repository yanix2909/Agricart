const DEFAULT_SUPABASE_URL = "https://afkwexvvuxwbpioqnelp.supabase.co";
const DEFAULT_SUPABASE_ANON_KEY =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFma3dleHZ2dXh3YnBpb3FuZWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5MzA3MjcsImV4cCI6MjA3ODUwNjcyN30.7r5j1xfWdJwiRZZm8AcOIaBp9VaXoD2QWE3WrGYZNyM";

// Admin Dashboard Manager
class AdminManager {
    constructor() {
        this.buildVersion = '2025-01-27-supabase-staff-migration';
        this.isCreatingStaff = false;
        this.supabaseUrl =
            window.SUPABASE_URL ||
            DEFAULT_SUPABASE_URL;
        this.supabaseAnonKey =
            window.SUPABASE_ANON_KEY ||
            window.firebaseConfig?.SUPABASE_ANON_KEY ||
            DEFAULT_SUPABASE_ANON_KEY;

        // Ensure globals exist for other modules
        if (!window.SUPABASE_URL) {
            window.SUPABASE_URL = this.supabaseUrl;
        }
        if (!window.SUPABASE_ANON_KEY) {
            window.SUPABASE_ANON_KEY = this.supabaseAnonKey;
        }
    }

    // Helper: get Supabase client with graceful fallback
    getSupabaseClient() {
        if (typeof window.getSupabaseClient === 'function') {
            return window.getSupabaseClient();
        }
        if (window.supabaseClient) {
            return window.supabaseClient;
        }
        return null;
    }

    // Helper: simple debounce utility scoped to this instance
    debounce(fn, delay = 500) {
        let timer;
        return (...args) => {
            clearTimeout(timer);
            timer = setTimeout(() => fn.apply(this, args), delay);
        };
    }

    // Helper: parse full_name into individual name components
    // This ensures consistent parsing across admin and staff views
    parseFullName(fullName) {
        if (!fullName || !fullName.trim()) {
            return { firstName: '', middleName: '', lastName: '', suffix: '' };
        }

        // Handle common suffixes (Jr, Sr, II, III, etc.)
        const suffixPattern = /\s+(Jr\.?|Sr\.?|II|III|IV|V|VI|VII|VIII|IX|X)$/i;
        const trimmedName = fullName.trim();
        const suffixMatch = trimmedName.match(suffixPattern);
        const suffix = suffixMatch ? suffixMatch[1] : '';
        const nameWithoutSuffix = suffix ? trimmedName.replace(suffixPattern, '').trim() : trimmedName;
        
        const nameParts = nameWithoutSuffix.split(/\s+/).filter(part => part);
        
        if (nameParts.length === 0) {
            return { firstName: '', middleName: '', lastName: '', suffix };
        } else if (nameParts.length === 1) {
            // Only one word - treat as first name
            return { firstName: nameParts[0], middleName: '', lastName: '', suffix };
        } else if (nameParts.length === 2) {
            // Two words - first name and last name
            return { firstName: nameParts[0], middleName: '', lastName: nameParts[1], suffix };
        } else {
            // Three or more words - need to determine if middle parts are part of first name or middle name
            // Heuristic: If middle parts are short (initials like "M.", "J") or very short words, 
            // they're likely part of the first name (e.g., "Mae M. Smith" -> first="Mae M.", last="Smith")
            const middleParts = nameParts.slice(1, -1);
            const lastPart = nameParts[nameParts.length - 1];
            
            // Check if a part is likely an initial (1-2 chars, possibly with period)
            const isInitial = (part) => {
                if (!part) return false;
                const trimmed = part.trim();
                // Remove periods and any trailing/leading punctuation
                const cleaned = trimmed.replace(/[\.\s]/g, '');
                // Must be 1-2 letters only (like "M", "M.", "Jr", "Jr.")
                if (cleaned.length >= 1 && cleaned.length <= 2 && /^[A-Za-z]+$/i.test(cleaned)) {
                    return true;
                }
                return false;
            };
            
            // Strategy: If there are multiple words and the last middle part is an initial,
            // treat everything before the initial as first name, initial as middle name
            // Example: "Joylyn Mae M. Olacao" -> first="Joylyn Mae", middle="M.", last="Olacao"
            // Example: "Mae M. Smith" -> first="Mae", middle="M.", last="Smith"
            
            const lastMiddlePart = middleParts[middleParts.length - 1];
            const isLastMiddleInitial = lastMiddlePart ? isInitial(lastMiddlePart.trim()) : false;
            
            if (isLastMiddleInitial && middleParts.length > 1) {
                // Last middle part is an initial AND there are multiple middle parts
                // Everything before the initial is first name, initial is middle name
                const firstNameParts = [nameParts[0], ...middleParts.slice(0, -1)];
                const result = {
                    firstName: firstNameParts.join(' ').trim(),
                    middleName: lastMiddlePart.trim(),
                    lastName: lastPart.trim(),
                    suffix
                };
                console.log(`parseFullName [${fullName}]: Multiple words + initial detected. Result:`, result);
                return result;
            } else if (isLastMiddleInitial && middleParts.length === 1) {
                // Single middle part that's an initial - keep as middle name
                const result = {
                    firstName: nameParts[0],
                    middleName: lastMiddlePart.trim(),
                    lastName: lastPart.trim(),
                    suffix
                };
                console.log(`parseFullName [${fullName}]: Single initial as middle. Result:`, result);
                return result;
            }
            
            // Standard separation: first word = first name, middle words = middle name, last word = last name
            const result = {
                firstName: nameParts[0],
                middleName: middleParts.join(' '),
                lastName: lastPart.trim(),
                suffix
            };
            console.log(`parseFullName [${fullName}]: Standard separation. Result:`, result);
            return result;
        }
    }

    // Helper: create a non-persistent Supabase client so admin session isn't replaced
    getEphemeralSignupClient() {
        if (typeof window.supabase === 'undefined') {
            console.error('window.supabase is not available for ephemeral client creation');
            return null;
        }
        const url = this.supabaseUrl;
        const anonKey = this.supabaseAnonKey;
        if (!url || !anonKey) {
            console.error('SUPABASE_URL or SUPABASE_ANON_KEY not configured on window for ephemeral client');
            return null;
        }
        try {
            return window.supabase.createClient(url, anonKey, {
                auth: {
                    persistSession: false,
                    autoRefreshToken: false,
                    detectSessionInUrl: false
                }
            });
        } catch (error) {
            console.error('Failed to create ephemeral Supabase client:', error);
            return null;
        }
    }

    // Check if an email is available across staff, customers, and riders
    async isEmailAvailable(email) {
        const supabase = this.getSupabaseClient();
        if (!supabase || !email) {
            return false;
        }

        const emailLower = email.toLowerCase();

        try {
            // Check staff
            const { data: staffRows, error: staffErr } = await supabase
                .from('staff')
                .select('uuid')
                .eq('email', emailLower)
                .limit(1);
            if (staffErr) throw staffErr;
            if (staffRows && staffRows.length > 0) return false;

            // Check customers
            const { data: customerRows, error: customerErr } = await supabase
                .from('customers')
                .select('uid')
                .eq('email', emailLower)
                .limit(1);
            if (customerErr) throw customerErr;
            if (customerRows && customerRows.length > 0) return false;

            // Check riders
            const { data: riderRows, error: riderErr } = await supabase
                .from('riders')
                .select('uid')
                .eq('email', emailLower)
                .limit(1);
            if (riderErr) throw riderErr;
            if (riderRows && riderRows.length > 0) return false;

            // No matches in any table
            return true;
        } catch (error) {
            console.error('Error checking email availability:', error);
            return false;
        }
    }

    // Check if a phone number is available across staff, customers, and riders
    async isPhoneAvailable(phone) {
        const supabase = this.getSupabaseClient();
        if (!supabase || !phone) {
            return false;
        }

        try {
            // Check staff (column: phone)
            const { data: staffRows, error: staffErr } = await supabase
                .from('staff')
                .select('uuid')
                .eq('phone', phone)
                .limit(1);
            if (staffErr) throw staffErr;
            if (staffRows && staffRows.length > 0) return false;

            // Check customers (column: phone_number)
            const { data: customerRows, error: customerErr } = await supabase
                .from('customers')
                .select('uid')
                .eq('phone_number', phone)
                .limit(1);
            if (customerErr) throw customerErr;
            if (customerRows && customerRows.length > 0) return false;

            // Check riders (column: phone_number)
            const { data: riderRows, error: riderErr } = await supabase
                .from('riders')
                .select('uid')
                .eq('phone_number', phone)
                .limit(1);
            if (riderErr) throw riderErr;
            if (riderRows && riderRows.length > 0) return false;

            return true;
        } catch (error) {
            console.error('Error checking phone availability:', error);
            return false;
        }
    }

    // Generate the next unique employee ID based on date + daily sequence
    // Example format: 20251204-001 (YYYYMMDD-###)
    async generateNextEmployeeId() {
        const supabase = this.getSupabaseClient();
        if (!supabase) {
            throw new Error('Supabase client not initialized');
        }

        // Build today's date prefix (local time) as YYYYMMDD-
        const nowDate = new Date();
        const yyyy = nowDate.getFullYear();
        const mm = String(nowDate.getMonth() + 1).padStart(2, '0');
        const dd = String(nowDate.getDate()).padStart(2, '0');
        const prefix = `${yyyy}${mm}${dd}-`;

        const { data: allStaff, error: staffError } = await supabase
            .from('staff')
            .select('employee_id')
            .like('employee_id', `${prefix}%`)
            .order('employee_id', { ascending: false })
            .limit(1);

        if (staffError) {
            console.error('Error generating next employee ID:', staffError);
            // Fallback to first sequence for today if query fails
            return `${prefix}001`;
        }

        let employeeId = `${prefix}001`;
        if (allStaff && allStaff.length > 0 && allStaff[0].employee_id) {
            const lastEmpId = String(allStaff[0].employee_id);
            // Extract numeric suffix after the prefix
            const suffix = lastEmpId.startsWith(prefix)
                ? lastEmpId.slice(prefix.length)
                : lastEmpId;
            const lastNum = parseInt(suffix, 10) || 0;
            employeeId = `${prefix}${String(lastNum + 1).padStart(3, '0')}`;
        }
        return employeeId;
    }

    initialize() {
        // Set up event listeners
        this.setupEventListeners();
    }

    setupEventListeners() {
        // Set up add staff button - try multiple times in case DOM isn't ready
        this.setupAddStaffButton();
        
        // Set up add rider button
        this.setupAddRiderButton();
        
        // Also set up on DOMContentLoaded if not already loaded
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => {
                this.setupAddStaffButton();
                this.setupAddRiderButton();
            });
        }
    }

    setupAddRiderButton() {
        const addRiderBtn = document.getElementById('addRiderBtn');
        if (addRiderBtn && !addRiderBtn._bound) {
            addRiderBtn.addEventListener('click', () => {
                this.showAddRiderModal();
            });
            addRiderBtn._bound = true;
            console.log('✅ Add Rider button event listener set up');
        } else if (addRiderBtn && addRiderBtn._bound) {
            console.log('Add Rider button already bound');
        } else {
            console.log('Add Rider button not found, will retry...');
            // Retry after a short delay
            setTimeout(() => this.setupAddRiderButton(), 500);
        }
    }

    setupAddStaffButton() {
        const addStaffBtn = document.getElementById('addStaffBtn');
        if (addStaffBtn && !addStaffBtn._bound) {
            addStaffBtn.addEventListener('click', () => {
                this.showAddStaffModal();
            });
            addStaffBtn._bound = true;
            console.log('✅ Add Staff button event listener set up');
        } else if (addStaffBtn && addStaffBtn._bound) {
            console.log('Add Staff button already bound');
        } else {
            console.log('Add Staff button not found, will retry...');
            // Retry after a short delay
            setTimeout(() => this.setupAddStaffButton(), 500);
        }
    }

    showAddStaffModal() {
        const barangaySelectHtml = (window.staffManager && typeof window.staffManager.renderBarangaySelect === 'function')
            ? window.staffManager.renderBarangaySelect('staffBarangay', '', true)
            : '<input type="text" id="staffBarangay" required>';

        const modalContent = `
            <div class="modal-content scrollable-modal">
                <div class="modal-header">
                    <h3>Add New Staff Member</h3>
                    <button class="close-modal" onclick="adminManager.closeModal()">&times;</button>
                </div>
                <form id="addStaffForm" style="padding: 24px; overflow-y: auto;">
                    <div style="display: flex; flex-direction: column; gap: 24px; max-width: 1200px; margin: 0 auto;">
                        <!-- Personal Information Section -->
                        <div class="form-section">
                            <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                <i class="fas fa-user"></i> Personal Information
                            </h4>
                            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                <div class="form-field">
                                    <label for="staffFirstName" class="required">First Name</label>
                                    <input type="text" id="staffFirstName" required>
                                </div>
                                <div class="form-field">
                                    <label for="staffMiddleName">Middle Name</label>
                                    <input type="text" id="staffMiddleName">
                                </div>
                                <div class="form-field">
                                    <label for="staffLastName" class="required">Last Name</label>
                                    <input type="text" id="staffLastName" required>
                                </div>
                                <div class="form-field">
                                    <label for="staffSuffix">Suffix</label>
                                    <input type="text" id="staffSuffix" placeholder="Jr., Sr., III, etc.">
                                </div>
                                <div class="form-field">
                                    <label for="email" class="required">Email</label>
                                    <input type="email" id="email" required>
                                    <small id="emailValidationMessage" style="display:block; font-size:12px; margin-top:4px;"></small>
                                </div>
                                <div class="form-field">
                                    <label for="phone" class="required">Phone</label>
                                    <input type="tel" id="phone" required maxlength="11">
                                    <small id="phoneValidationMessage" style="display:block; font-size:12px; margin-top:4px;"></small>
                                </div>
                            </div>
                        </div>

                        <!-- Home Address Section -->
                        <div class="form-section">
                            <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                <i class="fas fa-map-marker-alt"></i> Home Address
                            </h4>
                            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                <div class="form-field">
                                    <label for="staffStreet">Street</label>
                                    <input type="text" id="staffStreet">
                                </div>
                                <div class="form-field">
                                    <label for="staffSitio">Sitio</label>
                                    <input type="text" id="staffSitio">
                                </div>
                                <div class="form-field">
                                    <label for="staffBarangay" class="required">Barangay</label>
                                    ${barangaySelectHtml}
                                </div>
                                <div class="form-field">
                                    <label for="staffPostalCode">Postal Code</label>
                                    <input type="text" id="staffPostalCode" value="6541" readonly>
                                </div>
                                <div class="form-field">
                                    <label for="staffCity" class="required">City</label>
                                    <input type="text" id="staffCity" value="Ormoc" required readonly>
                                </div>
                                <div class="form-field">
                                    <label for="staffProvince" class="required">Province</label>
                                    <input type="text" id="staffProvince" value="Leyte" required readonly>
                                </div>
                            </div>
                        </div>

                        <!-- Password Section -->
                        <div class="form-section">
                            <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                <i class="fas fa-lock"></i> Password
                            </h4>
                            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                <div class="form-field">
                                    <label for="password" class="required">Password</label>
                                    <input type="password" id="password" required minlength="6">
                                </div>
                                <div class="form-field">
                                    <label for="confirmPassword" class="required">Confirm Password</label>
                                    <input type="password" id="confirmPassword" required minlength="6">
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="form-actions" style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #e2e8f0; display: flex; gap: 12px; justify-content: flex-end;">
                        <button type="button" class="secondary-btn" onclick="adminManager.closeModal()">Cancel</button>
                        <button type="submit" class="primary-btn">
                            <i class="fas fa-plus"></i> Create Staff Account
                        </button>
                    </div>
                </form>
            </div>
        `;

        // Create or update modal overlay
        let modalOverlay = document.getElementById('adminModal');
        if (!modalOverlay) {
            modalOverlay = document.createElement('div');
            modalOverlay.id = 'adminModal';
            modalOverlay.className = 'modal-overlay scrollable-overlay';
            document.body.appendChild(modalOverlay);
        }
        modalOverlay.innerHTML = modalContent;
        modalOverlay.classList.add('show');
        modalOverlay.style.display = 'flex';

        // Close modal when clicking on overlay (outside the content)
        modalOverlay.addEventListener('click', (e) => {
            if (e.target === modalOverlay) {
                this.closeModal();
            }
        });

        // Set up form submission
        const form = document.getElementById('addStaffForm');
        if (form) {
            form.addEventListener('submit', async (e) => {
                e.preventDefault();
                await this.createStaffAccount();
            });
        }

        // Set up live validation for email and phone fields
        const emailInput = document.getElementById('email');
        const phoneInput = document.getElementById('phone');
        const emailMsg = document.getElementById('emailValidationMessage');
        const phoneMsg = document.getElementById('phoneValidationMessage');

        const setInputState = (input, messageEl, isValid, message) => {
            if (!input) return;
            input.style.borderColor = isValid === null ? '' : (isValid ? '#4caf50' : '#f44336');
            input.style.boxShadow = isValid === null ? '' : (isValid ? '0 0 0 1px rgba(76, 175, 80, 0.4)' : '0 0 0 1px rgba(244, 67, 54, 0.4)');
            if (messageEl) {
                messageEl.textContent = message || '';
                messageEl.style.color = isValid === null ? '#666' : (isValid ? '#2e7d32' : '#c62828');
            }
        };

        if (emailInput) {
            const validateEmailLive = this.debounce(async () => {
                const value = emailInput.value.trim();
                if (!value) {
                    setInputState(emailInput, emailMsg, null, '');
                    return;
                }
                const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
                if (!emailRegex.test(value)) {
                    setInputState(emailInput, emailMsg, false, 'Please enter a valid email address.');
                    return;
                }
                const available = await this.isEmailAvailable(value);
                if (available) {
                    setInputState(emailInput, emailMsg, true, 'Email is available.');
                } else {
                    setInputState(emailInput, emailMsg, false, 'Email is already in use by another account.');
                }
            }, 600);
            emailInput.addEventListener('input', validateEmailLive);
        }

        if (phoneInput) {
            const validatePhoneLive = this.debounce(async () => {
                const value = phoneInput.value.replace(/\D/g, '');
                phoneInput.value = value; // enforce digits only
                if (!value) {
                    setInputState(phoneInput, phoneMsg, null, '');
                    return;
                }
                if (value.length !== 11) {
                    setInputState(phoneInput, phoneMsg, false, 'Phone number must be exactly 11 digits.');
                    return;
                }
                const available = await this.isPhoneAvailable(value);
                if (available) {
                    setInputState(phoneInput, phoneMsg, true, 'Phone number is available.');
                } else {
                    setInputState(phoneInput, phoneMsg, false, 'Phone number is already in use by another account.');
                }
            }, 600);
            phoneInput.addEventListener('input', validatePhoneLive);
                }

    }

    async createStaffAccount() {
        try {
            if (this.isCreatingStaff) {
                return; // Prevent double submission
            }

            const formData = {
                firstName: document.getElementById('staffFirstName').value.trim(),
                middleName: document.getElementById('staffMiddleName')?.value.trim() || null,
                lastName: document.getElementById('staffLastName').value.trim(),
                suffix: document.getElementById('staffSuffix')?.value.trim() || null,
                email: document.getElementById('email').value.trim(),
                phone: document.getElementById('phone').value.trim(),
                password: document.getElementById('password').value,
                confirmPassword: document.getElementById('confirmPassword').value,
                street: document.getElementById('staffStreet')?.value.trim() || null,
                sitio: document.getElementById('staffSitio')?.value.trim() || null,
                barangay: document.getElementById('staffBarangay').value.trim(),
                city: document.getElementById('staffCity').value.trim(),
                province: document.getElementById('staffProvince').value.trim(),
                postalCode: document.getElementById('staffPostalCode')?.value.trim() || '6541'
            };

            // Validation
            if (!formData.firstName || !formData.lastName || !formData.email || !formData.phone || 
                !formData.barangay || 
                !formData.city || !formData.province || !formData.password) {
                alert('Please fill in all required fields');
                return;
            }

            // Email format validation
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            if (!emailRegex.test(formData.email)) {
                alert('Please enter a valid email address.');
                return;
            }

            // Phone format validation (11 digits)
            const cleanedPhone = formData.phone.replace(/\D/g, '');
            if (cleanedPhone.length !== 11) {
                alert('Phone number must be exactly 11 digits.');
                return;
            }
            formData.phone = cleanedPhone;

            if (formData.password !== formData.confirmPassword) {
                alert('Passwords do not match');
                return;
            }

            if (formData.password.length < 6) {
                alert('Password must be at least 6 characters long');
                return;
            }

            // Get Supabase client with fallback
            let supabase = this.getSupabaseClient();
            
            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }
            
            // Enforce unique email across staff, customers, and riders
            const emailAvailable = await this.isEmailAvailable(formData.email);
            if (!emailAvailable) {
                alert('Email is already in use by another account (staff, customer, or rider).');
                return;
            }
            
            // Enforce unique phone across staff, customers, and riders
            const phoneAvailable = await this.isPhoneAvailable(formData.phone);
            if (!phoneAvailable) {
                alert('Phone number is already in use by another account (staff, customer, or rider).');
                return;
            }

            // Build full name from components
            let fullName = formData.firstName;
            if (formData.middleName) {
                fullName += ' ' + formData.middleName;
            }
            fullName += ' ' + formData.lastName;
            if (formData.suffix) {
                fullName += ' ' + formData.suffix;
            }

            // Build full address from components
            let fullAddressParts = [];
            if (formData.street) fullAddressParts.push(formData.street);
            if (formData.sitio) fullAddressParts.push(`Sitio ${formData.sitio}`);
            if (formData.barangay) fullAddressParts.push(formData.barangay);
            if (formData.city) fullAddressParts.push(formData.city);
            if (formData.province) fullAddressParts.push(formData.province);
            if (formData.postalCode) fullAddressParts.push(formData.postalCode);
            const fullAddress = fullAddressParts.length > 0 ? fullAddressParts.join(', ') : 'N/A';

            // Auto-generate Employee ID: date + daily sequence (e.g., 20251204-001)
            let employeeId = await this.generateNextEmployeeId();

            // Generate UUID for staff
            const staffUuid = crypto.randomUUID ? crypto.randomUUID() : 
                'staff_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);

            // Show loading state
            const submitBtn = document.querySelector('#addStaffForm button[type="submit"]');
            const originalBtnText = submitBtn ? submitBtn.innerHTML : '';
            if (submitBtn) {
                submitBtn.disabled = true;
                submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Creating auth user...';
            }
            this.isCreatingStaff = true;

            // Normalize email for auth + storage
            formData.email = formData.email.toLowerCase();
            
            // Create Supabase Auth user without affecting current admin session
            const signupClient = this.getEphemeralSignupClient();
            if (!signupClient) {
                if (submitBtn) {
                    submitBtn.disabled = false;
                    submitBtn.innerHTML = originalBtnText;
                }
                this.isCreatingStaff = false;
                alert('Supabase auth client not initialized. Please refresh the page.');
                return;
                }

            let authUserId = null;
            try {
                const { data: authData, error: signUpError } = await signupClient.auth.signUp({
                    email: formData.email,
                    password: formData.password,
                    options: {
                        emailRedirectTo: window.location.origin + '/index.html',
                        data: {
                            role: 'staff',
                            full_name: fullName,
                            employee_id: employeeId
                        }
                    }
                });

                if (signUpError) {
                    const message = signUpError.message || 'Failed to create Supabase auth user.';
                    console.error('Supabase auth sign-up error:', signUpError);
                if (submitBtn) {
                        submitBtn.disabled = false;
                        submitBtn.innerHTML = originalBtnText;
                    }
                    this.isCreatingStaff = false;
                    if (message.toLowerCase().includes('already registered')) {
                        alert('This email is already registered in Supabase Auth. Please use a different email.');
                    } else {
                        alert(message);
                    }
                    return;
                }

                authUserId = authData?.user?.id || null;
            } catch (signUpException) {
                console.error('Unexpected error during Supabase auth sign-up:', signUpException);
                if (submitBtn) {
                    submitBtn.disabled = false;
                    submitBtn.innerHTML = originalBtnText;
                }
                this.isCreatingStaff = false;
                alert('Unexpected error while creating Supabase auth user: ' + (signUpException?.message || 'Please try again.'));
                return;
            }

            if (submitBtn) {
                submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving staff profile...';
            }

            // Create staff profile data matching Supabase table columns
            // Use Unix timestamp in milliseconds for bigint columns
            // Note: Name is saved in a single 'full_name' column, and address is saved in a single 'address' column
            // Individual name and address fields (first_name, middle_name, street, barangay, etc.) do not exist in the schema
            const now = Date.now(); // Unix timestamp in milliseconds
            const baseStaffData = {
                uuid: staffUuid,
                full_name: fullName, // Built from first name, middle name, last name, suffix
                email: formData.email,
                phone: formData.phone,
                address: fullAddress, // Built from street, sitio, barangay, city, province, postal code
                password: formData.password, // Store password in Supabase (plain text for now)
                role: 'staff',
                status: 'active',
                created_at: now,
                updated_at: now,
                created_by: sessionStorage.getItem('staffUid') || sessionStorage.getItem('adminUid') || 'admin'
                // Note: auth_user_id is not stored here because the column does not exist yet in the Supabase schema
            };

            // Save staff data to Supabase with basic retry on employee_id uniqueness conflict
            let inserted = false;
            let lastInsertError = null;
            for (let attempt = 0; attempt < 3 && !inserted; attempt++) {
                const staffData = {
                    ...baseStaffData,
                    employee_id: employeeId
                };

            const { error: insertError } = await supabase
                .from('staff')
                .insert([staffData]);
            
                if (!insertError) {
                    inserted = true;
                    break;
                }

                lastInsertError = insertError;

                const msg = insertError.message || '';
                const details = insertError.details || '';
                const isDuplicateEmpId =
                    msg.includes('staff_employee_id_key') ||
                    details.includes('staff_employee_id_key') ||
                    msg.includes('duplicate key value violates unique constraint') && msg.includes('employee_id');

                if (isDuplicateEmpId) {
                    // Generate a new employee ID and retry
                    console.warn('Duplicate employee_id detected, regenerating and retrying insert...');
                    employeeId = await this.generateNextEmployeeId();
                    continue;
                }

                // For other errors, break immediately
                break;
            }

            if (!inserted) {
                throw new Error('Failed to create staff account: ' + (lastInsertError?.message || 'Unknown error'));
            }

            // Restore button state
            if (submitBtn) {
                submitBtn.disabled = false;
                submitBtn.innerHTML = originalBtnText;
            }
            this.isCreatingStaff = false;

            this.closeModal();
            this.showSuccessMessage('Staff account created and email verification sent');
            
            // Refresh staff list if staffManager exists
            if (window.staffManager && typeof window.staffManager.loadStaffData === 'function') {
                window.staffManager.loadStaffData();
            }

        } catch (error) {
            console.error('Error creating staff account:', error);
            const submitBtn = document.querySelector('#addStaffForm button[type="submit"]');
            if (submitBtn) {
                submitBtn.disabled = false;
                submitBtn.innerHTML = '<i class="fas fa-plus"></i> Create Staff Account';
            }
            this.isCreatingStaff = false;
            
            alert('Error creating staff account: ' + (error.message || 'An unexpected error occurred.'));
        }
    }

    closeModal() {
        const modal = document.getElementById('adminModal');
        if (modal) {
            modal.classList.remove('show');
            setTimeout(() => {
                modal.style.display = 'none';
                modal.innerHTML = '';
            }, 300); // Wait for fade out animation
        }
    }

    showSuccessMessage(message) {
        // Create or update success message element
        let successMsg = document.getElementById('adminSuccessMessage');
        if (!successMsg) {
            successMsg = document.createElement('div');
            successMsg.id = 'adminSuccessMessage';
            successMsg.style.cssText = 'position: fixed; top: 20px; right: 20px; background: #4caf50; color: white; padding: 16px 24px; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); z-index: 10000; display: flex; align-items: center; gap: 12px;';
            document.body.appendChild(successMsg);
        }
        successMsg.innerHTML = `<i class="fas fa-check-circle"></i> ${message}`;
        successMsg.style.display = 'flex';
        
        // Hide after 3 seconds
        setTimeout(() => {
            successMsg.style.display = 'none';
        }, 3000);
    }

    async toggleStaffStatus(id, currentStatus) {
        try {
            const newStatus = currentStatus === 'active' ? 'inactive' : 'active';
            const confirm = window.confirm(`Are you sure you want to ${newStatus === 'active' ? 'activate' : 'deactivate'} this staff member?`);
            
            if (!confirm) return;

            // Get Supabase client with fallback
            let supabase = null;
            if (typeof window.getSupabaseClient === 'function') {
                supabase = window.getSupabaseClient();
            } else if (window.supabaseClient) {
                supabase = window.supabaseClient;
            }
            
            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }
            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }

            // Use Unix timestamp in milliseconds for bigint column
            const now = Date.now();
            const { error: updateError } = await supabase
                .from('staff')
                .update({
                    status: newStatus,
                    updated_at: now
                })
                .eq('uuid', id);

            if (updateError) {
                throw new Error(updateError.message);
            }

            this.showSuccessMessage(`Staff member ${newStatus === 'active' ? 'activated' : 'deactivated'} successfully`);
            
            // Refresh staff list if staffManager exists
            if (window.staffManager && typeof window.staffManager.loadStaffData === 'function') {
                window.staffManager.loadStaffData();
            }

        } catch (error) {
            console.error('Error updating staff status:', error);
            alert('Error updating staff status: ' + error.message);
        }
    }

    escAttr(value) {
        if (value === null || value === undefined) return '';
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    _parseStaffAddress(address) {
        const defaults = {
            street: '',
            sitio: '',
            barangay: '',
            city: 'Ormoc',
            province: 'Leyte',
            postalCode: ''
        };

        if (!address) {
            return defaults;
        }

        const parts = address.split(',').map(part => part.trim()).filter(Boolean);
        let idx = 0;

        if (parts[idx] && !/^sitio\s+/i.test(parts[idx])) {
            defaults.street = parts[idx++];
        }

        if (parts[idx] && /^sitio\s+/i.test(parts[idx])) {
            defaults.sitio = parts[idx].replace(/^sitio\s+/i, '');
            idx++;
        }

        if (parts[idx]) {
            defaults.barangay = parts[idx++];
        }

        if (parts[idx]) {
            defaults.city = parts[idx++];
        }

        if (parts[idx]) {
            defaults.province = parts[idx++];
        }

        if (parts[idx]) {
            defaults.postalCode = parts[idx++];
        }

        return defaults;
    }

    async editStaff(id) {
        try {
            let supabase = null;
            if (typeof window.getSupabaseClient === 'function') {
                supabase = window.getSupabaseClient();
            } else if (window.supabaseClient) {
                supabase = window.supabaseClient;
            }

            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }

            const { data: staff, error } = await supabase
                .from('staff')
                .select('*')
                .eq('uuid', id)
                .single();

            if (error || !staff) {
                console.error('Failed to load staff record:', error);
                alert('Staff record not found.');
                return;
            }

            this._editingStaffOriginal = staff;

            // Parse full_name into individual components using the same logic as staff profile
            const parsedName = this.parseFullName(staff.full_name || '');
            console.log('Admin edit modal - Parsed name from full_name:', staff.full_name, '->', parsedName);
            
            const addressFields = this._parseStaffAddress(staff.address || '');
            // Use individual fields from database if available, otherwise parse from address
            const editStreet = staff.street || addressFields.street || '';
            const editSitio = staff.sitio || addressFields.sitio || '';
            const editBarangay = staff.barangay || addressFields.barangay || '';
            const editPostalCode = staff.postal_code || addressFields.postalCode || '6541';
            const editCity = staff.city || addressFields.city || 'Ormoc';
            const editProvince = staff.province || addressFields.province || 'Leyte';
            const barangaySelectHtml = (window.staffManager && typeof window.staffManager.renderBarangaySelect === 'function')
                ? window.staffManager.renderBarangaySelect('editStaffBarangay', editBarangay, true)
                : `<input type="text" id="editStaffBarangay" value="${this.escAttr(editBarangay)}" required>`;

            const modalContent = `
                <div class="modal-content scrollable-modal">
                    <div class="modal-header">
                        <h3>Edit Staff Account</h3>
                        <button class="close-modal" onclick="adminManager.closeModal()">&times;</button>
                    </div>
                    <form id="editStaffForm" style="padding: 24px; overflow-y: auto;">
                        <div style="display: flex; flex-direction: column; gap: 24px; max-width: 1200px; margin: 0 auto;">
                            <div class="form-section">
                                <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                    <i class="fas fa-user"></i> Personal Information
                                </h4>
                                <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                    <div class="form-field">
                                        <label for="editStaffFirstName" class="required">First Name</label>
                                        <input type="text" id="editStaffFirstName" value="${this.escAttr(parsedName.firstName)}" required>
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffMiddleName">Middle Name</label>
                                        <input type="text" id="editStaffMiddleName" value="${this.escAttr(parsedName.middleName)}">
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffLastName" class="required">Last Name</label>
                                        <input type="text" id="editStaffLastName" value="${this.escAttr(parsedName.lastName)}" required>
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffSuffix">Suffix</label>
                                        <input type="text" id="editStaffSuffix" value="${this.escAttr(parsedName.suffix)}" placeholder="Jr., Sr., III, etc.">
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffEmail" class="required">Email</label>
                                        <input type="email" id="editStaffEmail" value="${this.escAttr(staff.email || '')}" required>
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffPhone" class="required">Phone</label>
                                        <input type="tel" id="editStaffPhone" value="${this.escAttr(staff.phone || '')}" required>
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffStatus" class="required">Status</label>
                                        <select id="editStaffStatus" required>
                                            <option value="active" ${staff.status === 'active' ? 'selected' : ''}>Active</option>
                                            <option value="inactive" ${staff.status === 'inactive' ? 'selected' : ''}>Inactive</option>
                                        </select>
                                    </div>
                                </div>
                            </div>

                            <div class="form-section">
                                <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                    <i class="fas fa-map-marker-alt"></i> Home Address
                                </h4>
                                <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                    <div class="form-field">
                                        <label for="editStaffStreet">Street</label>
                                        <input type="text" id="editStaffStreet" value="${this.escAttr(editStreet)}">
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffSitio">Sitio</label>
                                        <input type="text" id="editStaffSitio" value="${this.escAttr(editSitio)}">
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffBarangay" class="required">Barangay</label>
                                        ${barangaySelectHtml}
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffPostalCode">Postal Code</label>
                                        <input type="text" id="editStaffPostalCode" value="${this.escAttr(editPostalCode)}" readonly>
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffCity" class="required">City</label>
                                        <input type="text" id="editStaffCity" value="${this.escAttr(editCity)}" required readonly>
                                    </div>
                                    <div class="form-field">
                                        <label for="editStaffProvince" class="required">Province</label>
                                        <input type="text" id="editStaffProvince" value="${this.escAttr(editProvince)}" required readonly>
                                    </div>
                                </div>
                            </div>

                        </div>

                        <div class="form-actions" style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #e2e8f0; display: flex; gap: 12px; justify-content: flex-end;">
                            <button type="button" class="secondary-btn" onclick="adminManager.closeModal()">Cancel</button>
                            <button type="submit" class="primary-btn">
                                <i class="fas fa-save"></i> Save Changes
                            </button>
                        </div>
                    </form>
                </div>
            `;

            let modalOverlay = document.getElementById('adminModal');
            if (!modalOverlay) {
                modalOverlay = document.createElement('div');
                modalOverlay.id = 'adminModal';
                modalOverlay.className = 'modal-overlay scrollable-overlay';
                document.body.appendChild(modalOverlay);
            }
            modalOverlay.innerHTML = modalContent;
            modalOverlay.classList.add('show');
            modalOverlay.style.display = 'flex';

            modalOverlay.addEventListener('click', (e) => {
                if (e.target === modalOverlay) {
                    this.closeModal();
                }
            });

            const form = document.getElementById('editStaffForm');
            if (form) {
                form.addEventListener('submit', async (event) => {
                    event.preventDefault();
                    await this.updateStaffAccount(id);
                });
            }
        } catch (error) {
            console.error('Error opening edit staff modal:', error);
            alert('Failed to open staff editor: ' + error.message);
        }
    }

    async updateStaffAccount(id) {
        try {
            if (!id) {
                alert('Invalid staff record');
                return;
            }

            const supabase = typeof window.getSupabaseClient === 'function'
                ? window.getSupabaseClient()
                : (window.supabaseClient || null);

            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }

            const firstName = document.getElementById('editStaffFirstName')?.value.trim();
            const middleName = document.getElementById('editStaffMiddleName')?.value.trim();
            const lastName = document.getElementById('editStaffLastName')?.value.trim();
            const suffix = document.getElementById('editStaffSuffix')?.value.trim();
            const email = document.getElementById('editStaffEmail')?.value.trim();
            const phone = document.getElementById('editStaffPhone')?.value.trim();
            const status = document.getElementById('editStaffStatus')?.value.trim();
            const street = document.getElementById('editStaffStreet')?.value.trim();
            const sitio = document.getElementById('editStaffSitio')?.value.trim();
            const barangayField = document.getElementById('editStaffBarangay');
            const barangay = barangayField ? barangayField.value.trim() : '';
            const postalCode = document.getElementById('editStaffPostalCode')?.value.trim() || '6541';
            const city = document.getElementById('editStaffCity')?.value.trim() || 'Ormoc';
            const province = document.getElementById('editStaffProvince')?.value.trim() || 'Leyte';

            if (!firstName || !lastName || !email || !phone || !status || !barangay) {
                alert('Please fill in all required fields.');
                return;
            }

            let fullName = firstName;
            if (middleName) fullName += ' ' + middleName;
            fullName += ' ' + lastName;
            if (suffix) fullName += ' ' + suffix;

            const emailLower = email.toLowerCase();
            const original = this._editingStaffOriginal || {};
            if (original.email && original.email.toLowerCase() !== emailLower) {
                const { data: existingStaff, error: emailError } = await supabase
                    .from('staff')
                    .select('uuid')
                    .eq('email', emailLower)
                    .neq('uuid', id)
                    .maybeSingle();

                if (emailError && emailError.code !== 'PGRST116') {
                    console.error('Email check failed:', emailError);
                    alert('Error checking email uniqueness: ' + emailError.message);
                    return;
                }

                if (existingStaff) {
                    alert('Email is already in use by another staff member.');
                    return;
                }
            }

            const addressParts = [];
            if (street) addressParts.push(street);
            if (sitio) addressParts.push(`Sitio ${sitio}`);
            addressParts.push(barangay);
            addressParts.push(city);
            addressParts.push(province);
            if (postalCode) addressParts.push(postalCode);
            const fullAddress = addressParts.join(', ');

            const submitBtn = document.querySelector('#editStaffForm button[type="submit"]');
            const originalBtnText = submitBtn ? submitBtn.innerHTML : '';
            if (submitBtn) {
                submitBtn.disabled = true;
                submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
            }

            // Get admin/staff name and role for tracking who updated
            // Since this is the admin dashboard, the user is always an admin
            const updaterName = sessionStorage.getItem('adminName') || 
                                sessionStorage.getItem('staffName') || 
                                sessionStorage.getItem('username') || 
                                'Admin';
            const updaterRole = 'Administrator';

            // Note: Name is saved in a single 'full_name' column, and address is saved in a single 'address' column
            // Individual name and address fields (first_name, middle_name, street, barangay, etc.) do not exist in the schema
            const updateData = {
                full_name: fullName,
                email: emailLower,
                phone,
                status,
                address: fullAddress,
                updated_at: Date.now(),
                last_updated_by_name: updaterName,
                last_updated_by_role: updaterRole
            };

            const { error: updateError } = await supabase
                .from('staff')
                .update(updateData)
                .eq('uuid', id);

            if (updateError) {
                throw new Error(updateError.message);
            }

            if (submitBtn) {
                submitBtn.disabled = false;
                submitBtn.innerHTML = originalBtnText || '<i class="fas fa-save"></i> Save Changes';
            }

            this.closeModal();
            this.showSuccessMessage('Staff account updated successfully');

            // Refresh staff management list
            if (window.staffManager && typeof window.staffManager.loadStaffData === 'function') {
                window.staffManager.loadStaffData();
            }
            
            // Refresh staff profile view if staff is viewing their profile
            if (window.staffManager && typeof window.staffManager.populateProfileSection === 'function') {
                window.staffManager.populateProfileSection();
            }
        } catch (error) {
            console.error('Error updating staff account:', error);
            const submitBtn = document.querySelector('#editStaffForm button[type="submit"]');
            if (submitBtn) {
                submitBtn.disabled = false;
                submitBtn.innerHTML = '<i class="fas fa-save"></i> Save Changes';
            }
            alert('Failed to update staff account: ' + (error.message || 'Unknown error'));
        }
    }

    showAddRiderModal() {
        const barangaySelectHtml = (window.staffManager && typeof window.staffManager.renderBarangaySelect === 'function')
            ? window.staffManager.renderBarangaySelect('riderBarangay', '', true)
            : '<input type="text" id="riderBarangay" required>';

        const modalContent = `
            <div class="modal-content scrollable-modal">
                <div class="modal-header">
                    <h3>Add New Rider</h3>
                    <button class="close-modal" onclick="adminManager.closeModal()">&times;</button>
                </div>
                <form id="addRiderForm" style="padding: 24px; overflow-y: auto;">
                    <div style="display: flex; flex-direction: column; gap: 24px; max-width: 1200px; margin: 0 auto;">
                        <!-- Personal Information Section -->
                        <div class="form-section">
                            <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                <i class="fas fa-user"></i> Personal Information
                            </h4>
                            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                <div class="form-field">
                                    <label for="riderFirstName" class="required">First Name</label>
                                    <input type="text" id="riderFirstName" required>
                                </div>
                                <div class="form-field">
                                    <label for="riderMiddleName">Middle Name</label>
                                    <input type="text" id="riderMiddleName">
                                </div>
                                <div class="form-field">
                                    <label for="riderLastName" class="required">Last Name</label>
                                    <input type="text" id="riderLastName" required>
                                </div>
                                <div class="form-field">
                                    <label for="riderSuffix">Suffix</label>
                                    <input type="text" id="riderSuffix" placeholder="Jr., Sr., III, etc.">
                                </div>
                                <div class="form-field">
                                    <label for="riderEmail" class="required">Email</label>
                                    <input type="email" id="riderEmail" required>
                                </div>
                                <div class="form-field">
                                    <label for="riderPhoneNumber" class="required">Phone Number</label>
                                    <input type="tel" id="riderPhoneNumber" required>
                                </div>
                                <div class="form-field">
                                    <label for="riderGender" class="required">Gender</label>
                                    <select id="riderGender" required>
                                        <option value="">Select Gender</option>
                                        <option value="Male">Male</option>
                                        <option value="Female">Female</option>
                                        <option value="Other">Other</option>
                                    </select>
                                </div>
                                <div class="form-field">
                                    <label for="riderBirthDate" class="required">Birth Date</label>
                                    <input type="date" id="riderBirthDate" required>
                                </div>
                                <div class="form-field">
                                    <label for="riderAge">Age</label>
                                    <input type="text" id="riderAge" placeholder="Auto-calculated" readonly style="background: #f9fafb;">
                                </div>
                                <div class="form-field">
                                    <label for="riderIdType" class="required">Valid ID Type</label>
                                    <input type="text" id="riderIdType" value="Driver's License" readonly style="background: #f9fafb;">
                                    <small style="color:#666;font-size:12px;">Only driver's license is accepted for rider accounts.</small>
                                </div>
                                <div class="form-field">
                                    <label for="riderLicenseNumber" class="required">License Number</label>
                                    <input type="text" id="riderLicenseNumber" required>
                                </div>
                            </div>
                        </div>

                        <!-- Home Address Section -->
                        <div class="form-section">
                            <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                <i class="fas fa-map-marker-alt"></i> Home Address
                            </h4>
                            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                <div class="form-field">
                                    <label for="riderStreet">Street</label>
                                    <input type="text" id="riderStreet">
                                </div>
                                <div class="form-field">
                                    <label for="riderSitio">Sitio</label>
                                    <input type="text" id="riderSitio">
                                </div>
                                <div class="form-field">
                                    <label for="riderBarangay" class="required">Barangay</label>
                                    ${barangaySelectHtml}
                                </div>
                                <div class="form-field">
                                    <label for="riderPostalCode">Postal Code</label>
                                    <input type="text" id="riderPostalCode">
                                </div>
                                <div class="form-field">
                                    <label for="riderCity" class="required">City</label>
                                    <input type="text" id="riderCity" value="Ormoc" required readonly>
                                </div>
                                <div class="form-field">
                                    <label for="riderProvince" class="required">Province</label>
                                    <input type="text" id="riderProvince" value="Leyte" required readonly>
                                </div>
                            </div>
                        </div>

                        <!-- Vehicle Information Section -->
                        <div class="form-section">
                            <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                <i class="fas fa-motorcycle"></i> Vehicle Information
                            </h4>
                            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                <div class="form-field">
                                    <label for="riderVehicleType" class="required">Vehicle Type</label>
                                    <select id="riderVehicleType" required>
                                        <option value="">Select Vehicle Type</option>
                                        <option value="Motorcycle">Motorcycle</option>
                                        <option value="Tricycle">Tricycle</option>
                                        <option value="Bicycle">Bicycle</option>
                                        <option value="Car">Car</option>
                                        <option value="Van">Van</option>
                                        <option value="Other">Other</option>
                                    </select>
                                </div>
                                <div class="form-field">
                                    <label for="riderVehicleNumber" class="required">Vehicle Number</label>
                                    <input type="text" id="riderVehicleNumber" required>
                                </div>
                                <div class="form-field">
                                    <label for="riderCarRegistrationNumber" style="white-space: nowrap;">OR/CR Number (optional)</label>
                                    <input type="text" id="riderCarRegistrationNumber" placeholder="Plate OR / CR number">
                                </div>
                            </div>
                        </div>

                        <!-- Password Section -->
                        <div class="form-section">
                            <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                <i class="fas fa-lock"></i> Password
                            </h4>
                            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                <div class="form-field">
                                    <label for="riderPassword" class="required">Password</label>
                                    <input type="password" id="riderPassword" required minlength="6">
                                </div>
                                <div class="form-field">
                                    <label for="riderConfirmPassword" class="required">Confirm Password</label>
                                    <input type="password" id="riderConfirmPassword" required minlength="6">
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- ID Photos Section (Full Width Below) -->
                    <div class="form-section" style="margin-top: 24px;">
                        <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                            <i class="fas fa-id-card"></i> Valid ID Photos
                        </h4>
                        <p class="form-description" style="margin-bottom: 16px; color: #666; font-size: 14px;">Upload both sides of the driver's license and the vehicle registration papers</p>
                        <div class="id-photos-grid" style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 20px;">
                            <div class="form-field">
                                <label for="riderIdFront" class="required">License Front Photo</label>
                                <input type="file" id="riderIdFront" accept="image/*" required>
                                <div id="riderIdFrontPreview" class="image-preview"></div>
                            </div>
                            <div class="form-field">
                                <label for="riderIdBack" class="required">License Back Photo</label>
                                <input type="file" id="riderIdBack" accept="image/*" required>
                                <div id="riderIdBackPreview" class="image-preview"></div>
                            </div>
                            <div class="form-field">
                                <label for="riderRegistrationFront">Registration Paper Photo 1 (optional)</label>
                                <input type="file" id="riderRegistrationFront" accept="image/*">
                                <div id="riderRegistrationFrontPreview" class="image-preview"></div>
                            </div>
                            <div class="form-field">
                                <label for="riderRegistrationBack">Registration Paper Photo 2 (optional)</label>
                                <input type="file" id="riderRegistrationBack" accept="image/*">
                                <div id="riderRegistrationBackPreview" class="image-preview"></div>
                            </div>
                        </div>
                    </div>
                    <div class="form-actions" style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #e2e8f0; display: flex; gap: 12px; justify-content: flex-end;">
                        <button type="button" class="secondary-btn" onclick="adminManager.closeModal()">Cancel</button>
                        <button type="submit" class="primary-btn">
                            <i class="fas fa-plus"></i> Create Rider Account
                        </button>
                    </div>
                </form>
            </div>
        `;

        // Create or update modal overlay
        let modalOverlay = document.getElementById('adminModal');
        if (!modalOverlay) {
            modalOverlay = document.createElement('div');
            modalOverlay.id = 'adminModal';
            modalOverlay.className = 'modal-overlay scrollable-overlay';
            document.body.appendChild(modalOverlay);
        }
        modalOverlay.innerHTML = modalContent;
        modalOverlay.classList.add('show');
        modalOverlay.style.display = 'flex';

        // Close modal when clicking on overlay (outside the content)
        modalOverlay.addEventListener('click', (e) => {
            if (e.target === modalOverlay) {
                this.closeModal();
            }
        });

        // Set up form submission
        const form = document.getElementById('addRiderForm');
        if (form) {
            form.addEventListener('submit', async (e) => {
                e.preventDefault();
                await this.createRiderAccount();
            });
        }

        // Set up image previews
        const frontInput = document.getElementById('riderIdFront');
        const backInput = document.getElementById('riderIdBack');
        const frontPreview = document.getElementById('riderIdFrontPreview');
        const backPreview = document.getElementById('riderIdBackPreview');
        const regFrontInput = document.getElementById('riderRegistrationFront');
        const regBackInput = document.getElementById('riderRegistrationBack');
        const regFrontPreview = document.getElementById('riderRegistrationFrontPreview');
        const regBackPreview = document.getElementById('riderRegistrationBackPreview');
        const birthInput = document.getElementById('riderBirthDate');
        const ageInput = document.getElementById('riderAge');

        const updateAge = () => {
            if (!birthInput || !ageInput) return;
            const value = birthInput.value;
            if (!value) {
                ageInput.value = '';
                return;
            }
            const birthDate = new Date(value);
            if (isNaN(birthDate.getTime())) {
                ageInput.value = '';
                return;
            }
            const today = new Date();
            let age = today.getFullYear() - birthDate.getFullYear();
            const monthDiff = today.getMonth() - birthDate.getMonth();
            if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
                age--;
            }
            ageInput.value = age >= 0 ? age.toString() : '';
        };

        if (birthInput && ageInput) {
            birthInput.addEventListener('change', updateAge);
            birthInput.addEventListener('blur', updateAge);
            updateAge();
        }

        if (frontInput && frontPreview) {
            frontInput.addEventListener('change', (e) => {
                const file = e.target.files[0];
                if (file) {
                    const reader = new FileReader();
                    reader.onload = (e) => {
                        frontPreview.innerHTML = `<img src="${e.target.result}" alt="Front ID Preview" style="max-width: 100%; border-radius: 8px;">`;
                    };
                    reader.readAsDataURL(file);
                }
            });
        }

        if (backInput && backPreview) {
            backInput.addEventListener('change', (e) => {
                const file = e.target.files[0];
                if (file) {
                    const reader = new FileReader();
                    reader.onload = (e) => {
                        backPreview.innerHTML = `<img src="${e.target.result}" alt="Back ID Preview" style="max-width: 100%; border-radius: 8px;">`;
                    };
                    reader.readAsDataURL(file);
                }
            });
        }

        if (regFrontInput && regFrontPreview) {
            regFrontInput.addEventListener('change', (e) => {
                const file = e.target.files[0];
                if (file) {
                    const reader = new FileReader();
                    reader.onload = (e) => {
                        regFrontPreview.innerHTML = `<img src="${e.target.result}" alt="Registration Paper 1" style="max-width: 100%; border-radius: 8px;">`;
                    };
                    reader.readAsDataURL(file);
                }
            });
        }

        if (regBackInput && regBackPreview) {
            regBackInput.addEventListener('change', (e) => {
                const file = e.target.files[0];
                if (file) {
                    const reader = new FileReader();
                    reader.onload = (e) => {
                        regBackPreview.innerHTML = `<img src="${e.target.result}" alt="Registration Paper 2" style="max-width: 100%; border-radius: 8px;">`;
                    };
                    reader.readAsDataURL(file);
                }
            });
        }
    }

    async createRiderAccount() {
        try {
            if (this.isCreatingRider) {
                console.log('Rider creation already in progress');
                return;
            }

            this.isCreatingRider = true;

            // Get form data
            const form = document.getElementById('addRiderForm');
            if (!form) {
                throw new Error('Rider form not found');
            }

            const formData = {
                firstName: document.getElementById('riderFirstName')?.value.trim(),
                middleName: document.getElementById('riderMiddleName')?.value.trim() || null,
                lastName: document.getElementById('riderLastName')?.value.trim(),
                suffix: document.getElementById('riderSuffix')?.value.trim() || null,
                email: document.getElementById('riderEmail')?.value.trim(),
                phoneNumber: document.getElementById('riderPhoneNumber')?.value.trim(),
                gender: document.getElementById('riderGender')?.value,
                birthDate: document.getElementById('riderBirthDate')?.value,
                street: document.getElementById('riderStreet')?.value.trim() || null,
                sitio: document.getElementById('riderSitio')?.value.trim() || null,
                barangay: document.getElementById('riderBarangay')?.value.trim(),
                city: document.getElementById('riderCity')?.value.trim(),
                province: document.getElementById('riderProvince')?.value.trim(),
                postalCode: document.getElementById('riderPostalCode')?.value.trim() || null,
                idType: document.getElementById('riderIdType')?.value || "Driver's License",
                licenseNumber: document.getElementById('riderLicenseNumber')?.value.trim(),
                vehicleType: document.getElementById('riderVehicleType')?.value,
                vehicleNumber: document.getElementById('riderVehicleNumber')?.value.trim(),
                carRegistrationNumber: document.getElementById('riderCarRegistrationNumber')?.value.trim() || null,
                password: document.getElementById('riderPassword')?.value,
                confirmPassword: document.getElementById('riderConfirmPassword')?.value
            };

            // Validate form data
            if (!formData.firstName || !formData.lastName || !formData.email || !formData.phoneNumber || 
                !formData.gender || !formData.birthDate || !formData.barangay || !formData.city || 
                !formData.province || !formData.idType || !formData.licenseNumber || 
                !formData.vehicleType || !formData.vehicleNumber || !formData.password) {
                throw new Error('Please fill in all required fields');
            }

            if (formData.password !== formData.confirmPassword) {
                throw new Error('Passwords do not match');
            }

            if (formData.password.length < 6) {
                throw new Error('Password must be at least 6 characters long');
            }

            // Get Supabase client
            let supabase = null;
            if (typeof window.getSupabaseClient === 'function') {
                supabase = window.getSupabaseClient();
            } else if (window.supabaseClient) {
                supabase = window.supabaseClient;
            }
            
            if (!supabase) {
                throw new Error('Supabase client not initialized. Please refresh the page.');
            }

            // Check if email already exists
            const { data: existingEmail, error: emailCheckError } = await supabase
                .from('riders')
                .select('uid')
                .eq('email', formData.email.toLowerCase())
                .single();

            if (existingEmail) {
                throw new Error('Email is already registered');
            }

            // Update button state
            const submitBtn = form.querySelector('button[type="submit"]');
            const originalBtnText = submitBtn ? submitBtn.innerHTML : '';
            if (submitBtn) {
                submitBtn.disabled = true;
                submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Creating...';
            }

            // Generate UUID for rider
            const riderUuid = 'rider_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);

            // Construct full name
            let fullName = formData.firstName;
            if (formData.middleName) {
                fullName += ' ' + formData.middleName;
            }
            fullName += ' ' + formData.lastName;
            if (formData.suffix) {
                fullName += ' ' + formData.suffix;
            }

            // Upload ID photos
            const idFrontFile = document.getElementById('riderIdFront')?.files[0];
            const idBackFile = document.getElementById('riderIdBack')?.files[0];
            const regFrontFile = document.getElementById('riderRegistrationFront')?.files[0];
            const regBackFile = document.getElementById('riderRegistrationBack')?.files[0];

            if (!idFrontFile || !idBackFile) {
                throw new Error('Please upload the license front and back photos.');
            }

            let idFrontPhoto = null;
            let idBackPhoto = null;
            let regFrontPhoto = null;
            let regBackPhoto = null;
            let uploadError = null;

            try {
                // Use FirebaseUtils to upload to Supabase Storage (riderid_image bucket)
                if (window.FirebaseUtils && typeof window.FirebaseUtils.uploadRiderIdPhoto === 'function') {
                    idFrontPhoto = await window.FirebaseUtils.uploadRiderIdPhoto(idFrontFile, riderUuid, 'front');
                    idBackPhoto = await window.FirebaseUtils.uploadRiderIdPhoto(idBackFile, riderUuid, 'back');
                    if (regFrontFile) {
                        regFrontPhoto = await window.FirebaseUtils.uploadRiderIdPhoto(regFrontFile, riderUuid, 'registration1');
                    }
                    if (regBackFile) {
                        regBackPhoto = await window.FirebaseUtils.uploadRiderIdPhoto(regBackFile, riderUuid, 'registration2');
                    }
                } else {
                    throw new Error('Photo upload utility not available');
                }
            } catch (error) {
                console.error('Error uploading ID photos:', error);
                uploadError = error;
                this.isCreatingRider = false;
                if (submitBtn) {
                    submitBtn.disabled = false;
                    submitBtn.innerHTML = originalBtnText;
                }
                alert('Error uploading ID photos: ' + uploadError.message);
                return;
            }

            // Hash password (using SHA256 like the rider app expects)
            const passwordHash = await this.hashPassword(formData.password);

            // Use Unix timestamp in milliseconds for bigint columns
            const now = Date.now();
            
            // Convert birth date to timestamp
            const birthDateTimestamp = formData.birthDate ? new Date(formData.birthDate).getTime() : null;

            // Build full address string from components
            let fullAddressParts = [];
            if (formData.street) fullAddressParts.push(formData.street);
            if (formData.sitio) fullAddressParts.push(`Sitio ${formData.sitio}`);
            if (formData.barangay) fullAddressParts.push(formData.barangay);
            if (formData.city) fullAddressParts.push(formData.city);
            if (formData.province) fullAddressParts.push(formData.province);
            if (formData.postalCode) fullAddressParts.push(formData.postalCode);
            const fullAddressDisplay = fullAddressParts.length > 0 ? fullAddressParts.join(', ') : 'N/A';

            // Create rider data matching Supabase table columns
            const riderData = {
                uid: riderUuid,
                first_name: formData.firstName,
                middle_name: formData.middleName,
                last_name: formData.lastName,
                suffix: formData.suffix,
                full_name: fullName,
                email: formData.email.toLowerCase(),
                phone_number: formData.phoneNumber,
                gender: formData.gender,
                birth_date: birthDateTimestamp,
                street: formData.street,
                sitio: formData.sitio,
                barangay: formData.barangay,
                city: formData.city,
                province: formData.province,
                postal_code: formData.postalCode,
                address: fullAddressDisplay, // Build address from components
                id_type: formData.idType,
                id_number: formData.licenseNumber,
                id_front_photo: idFrontPhoto,
                id_back_photo: idBackPhoto,
                id_verified: false,
                vehicle_type: formData.vehicleType,
                vehicle_number: formData.vehicleNumber,
                license_number: formData.licenseNumber,
                registration_paper_front: regFrontPhoto,
                registration_paper_back: regBackPhoto,
                car_registration_number: formData.carRegistrationNumber,
                login_password_hash: passwordHash,
                status: 'pending',
                is_active: true,
                is_online: false,
                total_deliveries: 0,
                created_at: now,
                created_by: sessionStorage.getItem('staffUid') || sessionStorage.getItem('adminUid') || 'admin'
            };

            // Save rider data to Supabase
            const { error: insertError } = await supabase
                .from('riders')
                .insert([riderData]);
            
            if (insertError) {
                throw new Error('Failed to create rider account: ' + insertError.message);
            }

            // Restore button state
            if (submitBtn) {
                submitBtn.disabled = false;
                submitBtn.innerHTML = originalBtnText;
            }
            this.isCreatingRider = false;

            this.closeModal();
            this.showSuccessMessage('Rider account created successfully');
            
            // Refresh rider list if staffManager exists
            if (window.staffManager && typeof window.staffManager.loadRidersManagementData === 'function') {
                window.staffManager.loadRidersManagementData();
            }

        } catch (error) {
            console.error('Error creating rider account:', error);
            const form = document.getElementById('addRiderForm');
            const submitBtn = form ? form.querySelector('button[type="submit"]') : null;
            if (submitBtn) {
                submitBtn.disabled = false;
                submitBtn.innerHTML = '<i class="fas fa-plus"></i> Create Rider Account';
            }
            this.isCreatingRider = false;
            
            alert('Error creating rider account: ' + (error.message || 'An unexpected error occurred.'));
        }
    }

    async hashPassword(password) {
        // Convert password to SHA256 hash (matching rider app implementation)
        const encoder = new TextEncoder();
        const data = encoder.encode(password);
        const hashBuffer = await crypto.subtle.digest('SHA-256', data);
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
        return hashHex;
    }

    async viewStaffDetails(id) {
        try {
            // Get Supabase client with fallback
            let supabase = null;
            if (typeof window.getSupabaseClient === 'function') {
                supabase = window.getSupabaseClient();
            } else if (window.supabaseClient) {
                supabase = window.supabaseClient;
            }
            
            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }
            
            const { data: member, error: queryError } = await supabase
                .from('staff')
                .select('*')
                .eq('uuid', id)
                .single();
            
            if (queryError || !member) {
                alert('Staff member not found');
                return;
            }
            
            const fullName = member.full_name || 'Unknown';
            const email = member.email || 'N/A';
            const phone = member.phone || 'N/A';
            const employeeId = member.employee_id || 'N/A';
            const address = member.address || 'N/A';
            const status = member.status || 'N/A';
            const lastUpdatedByName = member.last_updated_by_name || null;
            const lastUpdatedByRole = member.last_updated_by_role || null;
            // Legacy ID fields (no longer shown in UI)
            // const validIdType = member.valid_id_type || 'N/A';
            // const validIdNumber = member.valid_id_number || 'N/A';
            // const idFrontPhoto = member.id_front_photo_url || null;
            // const idBackPhoto = member.id_back_photo_url || null;
            
            // Format dates if available
            const createdTimestampRaw = member.created_at || null;
            const updatedTimestampRaw = member.updated_at || null;

            let createdAt = 'N/A';
            if (createdTimestampRaw) {
                const createdDate = typeof createdTimestampRaw === 'number' 
                    ? new Date(createdTimestampRaw) 
                    : new Date(createdTimestampRaw);
                if (!Number.isNaN(createdDate.getTime())) {
                    createdAt = createdDate.toLocaleString();
                }
            }

            let updatedAt = null;
            if (updatedTimestampRaw) {
                const updatedTimestamp = typeof updatedTimestampRaw === 'number'
                    ? updatedTimestampRaw
                    : Date.parse(updatedTimestampRaw);
                const createdTimestamp = createdTimestampRaw
                    ? (typeof createdTimestampRaw === 'number' ? createdTimestampRaw : Date.parse(createdTimestampRaw))
                    : null;

                if (!Number.isNaN(updatedTimestamp)) {
                    const isDifferentFromCreated = !createdTimestamp || Math.abs(updatedTimestamp - createdTimestamp) > 1000;
                    if (isDifferentFromCreated) {
                        const updatedDate = new Date(updatedTimestamp);
                        updatedAt = updatedDate.toLocaleString();
                    }
                }
            }
            
            // Status badge color
            const statusColor = status === 'active' ? '#4caf50' : '#f44336';
            const statusBg = status === 'active' ? '#e8f5e9' : '#ffebee';
            
            const modalContent = `
                <div class="modal-content scrollable-modal" style="padding: 0 !important; max-width: 600px !important;">
                    <div class="modal-header" style="margin: 0 !important; padding: 20px 24px; border-bottom: 1px solid #e2e8f0;">
                        <h3>Staff Details</h3>
                        <button class="close-modal" onclick="adminManager.closeModal()">&times;</button>
                    </div>
                    <div style="padding: 0; overflow-y: auto; width: 100%;">
                        <div style="display: grid; grid-template-columns: 1fr; gap: 0; width: 100%; margin: 0;">
                            <!-- Personal & Account Information -->
                            <div style="width: 100%;">
                                <div style="margin: 0; padding: 20px 24px; border-bottom: 1px solid #e2e8f0; width: 100%; box-sizing: border-box;">
                                    <h4 style="margin: 0 0 12px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                        <i class="fas fa-user"></i> Personal Information
                                    </h4>
                                    <div style="display: flex; flex-direction: column; gap: 12px;">
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Full Name</label>
                                            <div style="font-size: 16px; color: #333; padding: 10px 14px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; width: 100%; box-sizing: border-box;">${fullName}</div>
                                        </div>
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Email</label>
                                            <div style="font-size: 16px; color: #333; padding: 10px 14px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; width: 100%; box-sizing: border-box;">${email}</div>
                                        </div>
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Phone</label>
                                            <div style="font-size: 16px; color: #333; padding: 10px 14px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; width: 100%; box-sizing: border-box;">${phone}</div>
                                        </div>
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Employee ID</label>
                                            <div style="font-size: 16px; color: #333; padding: 10px 14px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; font-weight: 600; width: 100%; box-sizing: border-box;">${employeeId}</div>
                                        </div>
                                    </div>
                                </div>

                                <!-- Home Location -->
                                <div style="margin: 0; padding: 20px 24px; border-bottom: 1px solid #e2e8f0; width: 100%; box-sizing: border-box;">
                                    <h4 style="margin: 0 0 12px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                        <i class="fas fa-map-marker-alt"></i> Home Location
                                    </h4>
                                    <div style="display: flex; flex-direction: column; gap: 12px;">
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Address</label>
                                            <div style="font-size: 16px; color: #333; padding: 10px 14px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; min-height: 60px; white-space: pre-wrap; width: 100%; box-sizing: border-box;">${address}</div>
                                        </div>
                                    </div>
                                </div>
                                
                                <!-- Account Information -->
                                <div style="padding: 20px 24px; width: 100%; box-sizing: border-box; margin: 0;">
                                    <h4 style="margin: 0 0 12px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                        <i class="fas fa-info-circle"></i> Account Information
                                    </h4>
                                    <div style="display: flex; flex-direction: column; gap: 12px;">
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Status</label>
                                            <div style="display: inline-flex; align-items: center; gap: 8px; padding: 6px 12px; background: ${statusBg}; color: ${statusColor}; border-radius: 6px; font-weight: 600; width: fit-content;">
                                                <i class="fas fa-circle" style="font-size: 8px;"></i>
                                                ${status.toUpperCase()}
                                            </div>
                                        </div>
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Created At</label>
                                            <div style="font-size: 16px; color: #333; padding: 10px 14px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; width: 100%; box-sizing: border-box;">${createdAt}</div>
                                        </div>
                                        ${updatedAt ? `
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Last Updated At</label>
                                            <div style="font-size: 16px; color: #333; padding: 10px 14px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; width: 100%; box-sizing: border-box;">${updatedAt}</div>
                                        </div>` : ''}
                                        ${lastUpdatedByName ? `
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Last Updated By</label>
                                            <div style="font-size: 16px; color: #333; padding: 10px 14px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; width: 100%; box-sizing: border-box;">${lastUpdatedByName}${lastUpdatedByRole ? ` · ${lastUpdatedByRole}` : ''}</div>
                                        </div>` : ''}
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- Action Buttons -->
                        <div style="margin: 0; padding: 16px 24px; border-top: 1px solid #e2e8f0; display: flex; gap: 12px; justify-content: flex-end; width: 100%; box-sizing: border-box;">
                            <button type="button" class="secondary-btn" onclick="adminManager.closeModal()">Close</button>
                        </div>
                    </div>
                </div>
            `;

            // Create or update modal overlay
            let modalOverlay = document.getElementById('adminModal');
            if (!modalOverlay) {
                modalOverlay = document.createElement('div');
                modalOverlay.id = 'adminModal';
                modalOverlay.className = 'modal-overlay scrollable-overlay';
                document.body.appendChild(modalOverlay);
            }
            modalOverlay.innerHTML = modalContent;
            modalOverlay.classList.add('show');
            modalOverlay.style.display = 'flex';

            // Close modal when clicking on overlay (outside the content)
            modalOverlay.addEventListener('click', (e) => {
                if (e.target === modalOverlay) {
                    this.closeModal();
                }
            });

            // Set up image lightbox handlers
            const idPhotos = modalOverlay.querySelectorAll('.staff-id-photo');
            idPhotos.forEach(img => {
                img.addEventListener('click', (e) => {
                    e.stopPropagation();
                    const imageSrc = img.getAttribute('data-image-src');
                    if (imageSrc) {
                        this.showImageLightbox(imageSrc, img.alt || 'Staff ID Photo');
                    }
                });
            });
            
        } catch (error) {
            console.error('Error viewing staff details:', error);
            alert('Error loading staff details: ' + error.message);
        }
    }

    async removeStaff(id) {
        try {
            if (!confirm('Are you sure you want to permanently delete this staff member? This action cannot be undone.')) {
                return;
            }

            // Get Supabase client with fallback
            let supabase = null;
            if (typeof window.getSupabaseClient === 'function') {
                supabase = window.getSupabaseClient();
            } else if (window.supabaseClient) {
                supabase = window.supabaseClient;
            }
            
            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }

            const { error: deleteError } = await supabase
                .from('staff')
                .delete()
                .eq('uuid', id);

            if (deleteError) {
                throw new Error(deleteError.message);
            }

            this.showSuccessMessage('Staff member removed successfully');
            
            // Refresh staff list if staffManager exists
            if (window.staffManager && typeof window.staffManager.loadStaffData === 'function') {
                window.staffManager.loadStaffData();
            }
        } catch (error) {
            console.error('Error removing staff:', error);
            alert('Error removing staff: ' + error.message);
        }
    }

    async viewRiderDetails(id) {
        try {
            // Get Supabase client with fallback
            let supabase = null;
            if (typeof window.getSupabaseClient === 'function') {
                supabase = window.getSupabaseClient();
            } else if (window.supabaseClient) {
                supabase = window.supabaseClient;
            }
            
            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }
            
            const { data: rider, error: queryError } = await supabase
                .from('riders')
                .select('*')
                .eq('uid', id)
                .single();
            
            if (queryError || !rider) {
                alert('Rider not found');
                return;
            }
            
            // Extract rider data
            const fullName = rider.full_name || 'Unknown';
            const firstName = rider.first_name || 'N/A';
            const middleName = rider.middle_name || '';
            const lastName = rider.last_name || 'N/A';
            const suffix = rider.suffix || '';
            const email = rider.email || 'N/A';
            const phoneNumber = rider.phone_number || 'N/A';
            const gender = rider.gender || 'N/A';
            const birthDateRaw = rider.birth_date ? new Date(rider.birth_date) : null;
            const birthDate = birthDateRaw ? birthDateRaw.toLocaleDateString() : 'N/A';
            let ageDisplay = 'N/A';
            if (birthDateRaw && !isNaN(birthDateRaw.getTime())) {
                const today = new Date();
                let age = today.getFullYear() - birthDateRaw.getFullYear();
                const m = today.getMonth() - birthDateRaw.getMonth();
                if (m < 0 || (m === 0 && today.getDate() < birthDateRaw.getDate())) {
                    age--;
                }
                if (age >= 0) ageDisplay = age.toString();
            }
            const street = rider.street || '';
            const sitio = rider.sitio || '';
            const barangay = rider.barangay || 'N/A';
            const city = rider.city || 'N/A';
            const province = rider.province || 'N/A';
            const postalCode = rider.postal_code || '';
            const address = rider.address || 'N/A';
            const idType = rider.id_type || 'N/A';
            const idNumber = rider.id_number || 'N/A';
            const idFrontPhoto = rider.id_front_photo || null;
            const idBackPhoto = rider.id_back_photo || null;
            const vehicleType = rider.vehicle_type || 'N/A';
            const vehicleNumber = rider.vehicle_number || 'N/A';
            const licenseNumber = rider.license_number || 'N/A';
            const carRegistrationNumber = rider.car_registration_number || 'N/A';
            const regFrontPhoto = rider.registration_paper_front || null;
            const regBackPhoto = rider.registration_paper_back || null;
            const isActive = rider.is_active === true;
            let totalDeliveries = rider.total_deliveries || 0;

            // Fetch accurate successful deliveries (delivered/completed)
            // Check both orders and delivery_orders tables since delivery status might be in either
            try {
                // First, try to get count from orders table using rider_id
                const { count: deliveredCountOrders, error: deliveredErrorOrders } = await supabase
                    .from('orders')
                    .select('id', { count: 'exact', head: true })
                    .eq('rider_id', id)
                    .in('status', ['delivered', 'completed']);
                
                // Also check delivery_orders table (primary source for delivery status)
                const { count: deliveredCountDeliveryOrders, error: deliveredErrorDeliveryOrders } = await supabase
                    .from('delivery_orders')
                    .select('id', { count: 'exact', head: true })
                    .eq('rider_id', id)
                    .in('status', ['delivered', 'completed']);
                
                // Use the higher count (in case data is split between tables)
                let countFromOrders = 0;
                let countFromDeliveryOrders = 0;
                
                if (!deliveredErrorOrders && typeof deliveredCountOrders === 'number') {
                    countFromOrders = deliveredCountOrders;
                }
                
                if (!deliveredErrorDeliveryOrders && typeof deliveredCountDeliveryOrders === 'number') {
                    countFromDeliveryOrders = deliveredCountDeliveryOrders;
                }
                
                // Use the maximum count (some orders might only be in one table)
                totalDeliveries = Math.max(countFromOrders, countFromDeliveryOrders);
                
                // If we got a valid count, update the rider's total_deliveries field for future reference
                if (totalDeliveries > 0 && totalDeliveries !== (rider.total_deliveries || 0)) {
                    try {
                        await supabase
                            .from('riders')
                            .update({ total_deliveries: totalDeliveries })
                            .eq('uid', id);
                    } catch (updateErr) {
                        console.warn('Unable to update rider total_deliveries:', updateErr);
                    }
                }
            } catch (err) {
                console.warn('Unable to load delivery count, using stored total_deliveries', err);
            }

            let updatedAt = null;
            if (rider.updated_at) {
                const updatedDate = typeof rider.updated_at === 'number' 
                    ? new Date(rider.updated_at) 
                    : new Date(rider.updated_at);
                if (!isNaN(updatedDate.getTime())) {
                    updatedAt = updatedDate.toLocaleString();
                }
            }
            
            // Format dates
            let createdAt = 'N/A';
            if (rider.created_at) {
                const createdDate = typeof rider.created_at === 'number' 
                    ? new Date(rider.created_at) 
                    : new Date(rider.created_at);
                createdAt = createdDate.toLocaleString();
            }
            
            // Status badge colors - Active (green) or Deactivated (red)
            const statusText = isActive ? 'Active' : 'Deactivated';
            const statusColor = isActive ? '#4caf50' : '#f44336';
            const statusBg = isActive ? '#e8f5e9' : '#ffebee';
            
            // Build full address string
            let fullAddressParts = [];
            if (street) fullAddressParts.push(street);
            if (sitio) fullAddressParts.push(`Sitio ${sitio}`);
            if (barangay) fullAddressParts.push(barangay);
            if (city) fullAddressParts.push(city);
            if (province) fullAddressParts.push(province);
            if (postalCode) fullAddressParts.push(postalCode);
            const fullAddressDisplay = fullAddressParts.length > 0 ? fullAddressParts.join(', ') : address;
            
            const modalContent = `
                <div class="modal-content scrollable-modal">
                    <div class="modal-header">
                        <h3>Rider Details</h3>
                        <button class="close-modal" onclick="adminManager.closeModal()">&times;</button>
                    </div>
                    <div style="padding: 24px; overflow-y: auto;">
                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 24px;">
                            <!-- Left Column - Personal & Account Information -->
                            <div>
                                <!-- Personal Information -->
                                <div style="margin-bottom: 24px;">
                                    <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                        <i class="fas fa-user"></i> Personal Information
                                    </h4>
                                    <div style="display: flex; flex-direction: column; gap: 16px;">
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Full Name</label>
                                            <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; font-weight: 600;">${fullName}</div>
                                        </div>
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Email</label>
                                            <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${email}</div>
                                        </div>
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Phone Number</label>
                                            <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${phoneNumber}</div>
                                        </div>
                                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
                                            <div style="display: flex; flex-direction: column; gap: 4px;">
                                                <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Gender</label>
                                                <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${gender}</div>
                                            </div>
                                            <div style="display: flex; flex-direction: column; gap: 4px;">
                                                <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Birth Date</label>
                                                <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${birthDate}</div>
                                            </div>
                                            <div style="display: flex; flex-direction: column; gap: 4px;">
                                                <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Age</label>
                                                <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${ageDisplay}</div>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                                
                                <!-- Address Information -->
                                <div style="margin-bottom: 24px;">
                                    <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                        <i class="fas fa-map-marker-alt"></i> Address Information
                                    </h4>
                                    <div style="display: flex; flex-direction: column; gap: 16px;">
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Full Address</label>
                                            <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; min-height: 60px; white-space: pre-wrap;">${fullAddressDisplay}</div>
                                        </div>
                                    </div>
                                </div>
                                
                                <!-- Account Information -->
                                <div>
                                    <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                        <i class="fas fa-info-circle"></i> Account Information
                                    </h4>
                                    <div style="display: flex; flex-direction: column; gap: 16px;">
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Status</label>
                                            <div style="display: inline-flex; align-items: center; gap: 8px; padding: 6px 12px; background: ${statusBg}; color: ${statusColor}; border-radius: 6px; font-weight: 600; width: fit-content;">
                                                <i class="fas fa-circle" style="font-size: 8px;"></i>
                                                ${statusText.toUpperCase()}
                                            </div>
                                        </div>
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Total Deliveries</label>
                                            <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; font-weight: 600;">${totalDeliveries}</div>
                                        </div>
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Created At</label>
                                            <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${createdAt}</div>
                                        </div>
                                        ${updatedAt ? `
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Last Updated At</label>
                                            <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${updatedAt}</div>
                                        </div>` : ''}
                                    </div>
                                </div>
                            </div>
                            
                            <!-- Right Column - ID & Vehicle Information -->
                            <div>
                                <!-- ID Information -->
                                <div style="margin-bottom: 24px;">
                                    <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                        <i class="fas fa-id-card"></i> ID Information
                                    </h4>
                                    <div style="display: flex; flex-direction: column; gap: 16px;">
                                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
                                            <div style="display: flex; flex-direction: column; gap: 4px;">
                                                <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">ID Type</label>
                                                <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${idType}</div>
                                            </div>
                                            <div style="display: flex; flex-direction: column; gap: 4px;">
                                                <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">License Number</label>
                                                <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${licenseNumber}</div>
                                            </div>
                                        </div>
                                        <div>
                                            <label style="display: block; font-size: 12px; font-weight: 600; color: #666; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px;">ID Front Photo</label>
                                            ${idFrontPhoto ? 
                                                `<img src="${idFrontPhoto}" alt="ID Front" class="rider-id-photo" data-image-src="${idFrontPhoto}" style="width: 100%; max-width: 100%; border-radius: 8px; border: 2px solid #e2e8f0; cursor: pointer; transition: transform 0.2s ease;" onmouseover="this.style.transform='scale(1.02)'" onmouseout="this.style.transform='scale(1)'">` 
                                                : '<div style="padding: 40px; text-align: center; background: #f8fafc; border: 2px dashed #e2e8f0; border-radius: 8px; color: #999;"><i class="fas fa-image" style="font-size: 32px; margin-bottom: 8px; display: block;"></i>No photo available</div>'
                                            }
                                        </div>
                                        <div>
                                            <label style="display: block; font-size: 12px; font-weight: 600; color: #666; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px;">ID Back Photo</label>
                                            ${idBackPhoto ? 
                                                `<img src="${idBackPhoto}" alt="ID Back" class="rider-id-photo" data-image-src="${idBackPhoto}" style="width: 100%; max-width: 100%; border-radius: 8px; border: 2px solid #e2e8f0; cursor: pointer; transition: transform 0.2s ease;" onmouseover="this.style.transform='scale(1.02)'" onmouseout="this.style.transform='scale(1)'">` 
                                                : '<div style="padding: 40px; text-align: center; background: #f8fafc; border: 2px dashed #e2e8f0; border-radius: 8px; color: #999;"><i class="fas fa-image" style="font-size: 32px; margin-bottom: 8px; display: block;"></i>No photo available</div>'
                                            }
                                        </div>
                                        <div>
                                            <label style="display: block; font-size: 12px; font-weight: 600; color: #666; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px;">Registration Paper Photo 1</label>
                                            ${regFrontPhoto ? 
                                                `<img src="${regFrontPhoto}" alt="Registration Paper 1" class="rider-id-photo" data-image-src="${regFrontPhoto}" style="width: 100%; max-width: 100%; border-radius: 8px; border: 2px solid #e2e8f0; cursor: pointer; transition: transform 0.2s ease;" onmouseover="this.style.transform='scale(1.02)'" onmouseout="this.style.transform='scale(1)'">` 
                                                : '<div style="padding: 24px; text-align: center; background: #f8fafc; border: 2px dashed #e2e8f0; border-radius: 8px; color: #999;"><i class="fas fa-image" style="font-size: 20px; margin-bottom: 6px; display: block;"></i>No photo available</div>'
                                            }
                                        </div>
                                        <div>
                                            <label style="display: block; font-size: 12px; font-weight: 600; color: #666; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px;">Registration Paper Photo 2</label>
                                            ${regBackPhoto ? 
                                                `<img src="${regBackPhoto}" alt="Registration Paper 2" class="rider-id-photo" data-image-src="${regBackPhoto}" style="width: 100%; max-width: 100%; border-radius: 8px; border: 2px solid #e2e8f0; cursor: pointer; transition: transform 0.2s ease;" onmouseover="this.style.transform='scale(1.02)'" onmouseout="this.style.transform='scale(1)'">` 
                                                : '<div style="padding: 24px; text-align: center; background: #f8fafc; border: 2px dashed #e2e8f0; border-radius: 8px; color: #999;"><i class="fas fa-image" style="font-size: 20px; margin-bottom: 6px; display: block;"></i>No photo available</div>'
                                            }
                                        </div>
                                    </div>
                                </div>
                                
                                <!-- Vehicle Information -->
                                <div>
                                    <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                        <i class="fas fa-motorcycle"></i> Vehicle Information
                                    </h4>
                                    <div style="display: flex; flex-direction: column; gap: 16px;">
                                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
                                            <div style="display: flex; flex-direction: column; gap: 4px;">
                                                <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Vehicle Type</label>
                                                <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${vehicleType}</div>
                                            </div>
                                            <div style="display: flex; flex-direction: column; gap: 4px;">
                                                <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Vehicle Number</label>
                                                <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0; font-weight: 600;">${vehicleNumber}</div>
                                            </div>
                                        </div>
                                        <div style="display: flex; flex-direction: column; gap: 4px;">
                                            <label style="font-size: 12px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">OR/CR Number</label>
                                            <div style="font-size: 15px; color: #333; padding: 8px 12px; background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;">${carRegistrationNumber}</div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- Action Buttons -->
                        <div style="margin-top: 24px; padding-top: 20px; border-top: 1px solid #e2e8f0; display: flex; gap: 12px; justify-content: flex-end;">
                            <button type="button" class="secondary-btn" onclick="adminManager.closeModal()">Close</button>
                        </div>
                    </div>
                </div>
            `;

            // Create or update modal overlay
            let modalOverlay = document.getElementById('adminModal');
            if (!modalOverlay) {
                modalOverlay = document.createElement('div');
                modalOverlay.id = 'adminModal';
                modalOverlay.className = 'modal-overlay scrollable-overlay';
                document.body.appendChild(modalOverlay);
            }
            modalOverlay.innerHTML = modalContent;
            modalOverlay.classList.add('show');
            modalOverlay.style.display = 'flex';

            // Close modal when clicking on overlay (outside the content)
            modalOverlay.addEventListener('click', (e) => {
                if (e.target === modalOverlay) {
                    this.closeModal();
                }
            });

            // Set up image lightbox handlers
            const idPhotos = modalOverlay.querySelectorAll('.rider-id-photo');
            idPhotos.forEach(img => {
                img.addEventListener('click', (e) => {
                    e.stopPropagation();
                    const imageSrc = img.getAttribute('data-image-src');
                    if (imageSrc) {
                        this.showImageLightbox(imageSrc, img.alt || 'Rider ID Photo');
                    }
                });
            });
            
        } catch (error) {
            console.error('Error viewing rider details:', error);
            alert('Error loading rider details: ' + error.message);
        }
    }

    showImageLightbox(imageSrc, imageAlt = 'Image') {
        // Create lightbox overlay
        const lightboxOverlay = document.createElement('div');
        lightboxOverlay.id = 'imageLightboxOverlay';
        lightboxOverlay.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.9);
            z-index: 20000;
            display: flex;
            align-items: center;
            justify-content: center;
            opacity: 0;
            transition: opacity 0.3s ease;
            cursor: pointer;
        `;

        // Create lightbox content container
        const lightboxContent = document.createElement('div');
        lightboxContent.style.cssText = `
            position: relative;
            max-width: 90vw;
            max-height: 90vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 16px;
        `;

        // Create close button
        const closeBtn = document.createElement('button');
        closeBtn.innerHTML = '&times;';
        closeBtn.style.cssText = `
            position: absolute;
            top: -40px;
            right: 0;
            background: rgba(255, 255, 255, 0.2);
            border: none;
            color: white;
            font-size: 32px;
            width: 40px;
            height: 40px;
            border-radius: 50%;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: background 0.2s ease;
            z-index: 20001;
        `;
        closeBtn.onmouseover = () => closeBtn.style.background = 'rgba(255, 255, 255, 0.3)';
        closeBtn.onmouseout = () => closeBtn.style.background = 'rgba(255, 255, 255, 0.2)';

        // Create image element
        const lightboxImage = document.createElement('img');
        lightboxImage.src = imageSrc;
        lightboxImage.alt = imageAlt;
        lightboxImage.style.cssText = `
            max-width: 100%;
            max-height: 85vh;
            border-radius: 8px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
            object-fit: contain;
            cursor: default;
        `;

        // Create image label
        const imageLabel = document.createElement('div');
        imageLabel.textContent = imageAlt;
        imageLabel.style.cssText = `
            color: white;
            font-size: 14px;
            font-weight: 500;
            text-align: center;
            padding: 8px 16px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 6px;
        `;

        // Assemble lightbox
        lightboxContent.appendChild(closeBtn);
        lightboxContent.appendChild(lightboxImage);
        lightboxContent.appendChild(imageLabel);
        lightboxOverlay.appendChild(lightboxContent);

        // Add to document
        document.body.appendChild(lightboxOverlay);

        // Trigger fade-in animation
        setTimeout(() => {
            lightboxOverlay.style.opacity = '1';
        }, 10);

        // Close handlers
        const closeLightbox = () => {
            lightboxOverlay.style.opacity = '0';
            setTimeout(() => {
                if (lightboxOverlay.parentNode) {
                    lightboxOverlay.parentNode.removeChild(lightboxOverlay);
                }
            }, 300);
        };

        closeBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            closeLightbox();
        });

        lightboxOverlay.addEventListener('click', (e) => {
            if (e.target === lightboxOverlay || e.target === lightboxContent) {
                closeLightbox();
            }
        });

        // Close on Escape key
        const escapeHandler = (e) => {
            if (e.key === 'Escape' || e.keyCode === 27) {
                closeLightbox();
                document.removeEventListener('keydown', escapeHandler);
            }
        };
        document.addEventListener('keydown', escapeHandler);
    }

    async toggleRiderStatus(id, currentStatus) {
        try {
            const newStatus = !currentStatus;
            const confirmMsg = `Are you sure you want to ${newStatus ? 'activate' : 'deactivate'} this rider?`;
            if (!confirm(confirmMsg)) return;

            // Get Supabase client
            let supabase = null;
            if (typeof window.getSupabaseClient === 'function') {
                supabase = window.getSupabaseClient();
            } else if (window.supabaseClient) {
                supabase = window.supabaseClient;
            }
            
            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }

            const { error: updateError } = await supabase
                .from('riders')
                .update({
                    is_active: newStatus
                })
                .eq('uid', id);

            if (updateError) {
                throw new Error(updateError.message);
            }

            this.showSuccessMessage(`Rider ${newStatus ? 'activated' : 'deactivated'} successfully`);
            
            // Refresh rider list if staffManager exists
            if (window.staffManager && typeof window.staffManager.loadRidersManagementData === 'function') {
                window.staffManager.loadRidersManagementData();
            }

        } catch (error) {
            console.error('Error toggling rider status:', error);
            alert('Error updating rider status: ' + error.message);
        }
    }

    async editRider(id) {
        try {
            let supabase = null;
            if (typeof window.getSupabaseClient === 'function') {
                supabase = window.getSupabaseClient();
            } else if (window.supabaseClient) {
                supabase = window.supabaseClient;
            }

            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }

            const { data: rider, error } = await supabase
                .from('riders')
                .select('*')
                .eq('uid', id)
                .single();

            if (error || !rider) {
                console.error('Failed to load rider record:', error);
                alert('Rider record not found.');
                return;
            }

            this._editingRiderOriginal = rider;

            // Build address fields for editing
            const addressFields = {
                street: rider.street || '',
                sitio: rider.sitio || '',
                barangay: rider.barangay || '',
                postalCode: rider.postal_code || '',
                city: rider.city || 'Ormoc',
                province: rider.province || 'Leyte'
            };

            const barangaySelectHtml = (window.staffManager && typeof window.staffManager.renderBarangaySelect === 'function')
                ? window.staffManager.renderBarangaySelect('editRiderBarangay', addressFields.barangay, true)
                : `<input type="text" id="editRiderBarangay" value="${this.escAttr(addressFields.barangay)}" required>`;

            // Convert birth_date from timestamp to date string for input
            let birthDateStr = '';
            if (rider.birth_date) {
                const birthDate = typeof rider.birth_date === 'number' 
                    ? new Date(rider.birth_date) 
                    : new Date(rider.birth_date);
                birthDateStr = birthDate.toISOString().split('T')[0];
            }

            const idFrontPreview = rider.id_front_photo
                ? `<img src="${this.escAttr(rider.id_front_photo)}" alt="Current ID Front" style="max-width:100%; border-radius:8px; border:1px solid #e2e8f0; margin-top:8px;">`
                : '<div style="padding: 16px; border: 1px dashed #e2e8f0; border-radius: 8px; color: #888;">No front photo uploaded</div>';
            const idBackPreview = rider.id_back_photo
                ? `<img src="${this.escAttr(rider.id_back_photo)}" alt="Current ID Back" style="max-width:100%; border-radius:8px; border:1px solid #e2e8f0; margin-top:8px;">`
                : '<div style="padding: 16px; border: 1px dashed #e2e8f0; border-radius: 8px; color: #888;">No back photo uploaded</div>';

            const modalContent = `
                <div class="modal-content scrollable-modal">
                    <div class="modal-header">
                        <h3>Edit Rider Account</h3>
                        <button class="close-modal" onclick="adminManager.closeModal()">&times;</button>
                    </div>
                    <form id="editRiderForm" style="padding: 24px; overflow-y: auto;">
                        <div style="display: flex; flex-direction: column; gap: 24px; max-width: 1200px; margin: 0 auto;">
                            <div class="form-section">
                                <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                    <i class="fas fa-user"></i> Personal Information
                                </h4>
                                <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                    <div class="form-field">
                                        <label for="editRiderFirstName" class="required">First Name</label>
                                        <input type="text" id="editRiderFirstName" value="${this.escAttr(rider.first_name || '')}" required>
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderMiddleName">Middle Name</label>
                                        <input type="text" id="editRiderMiddleName" value="${this.escAttr(rider.middle_name || '')}">
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderLastName" class="required">Last Name</label>
                                        <input type="text" id="editRiderLastName" value="${this.escAttr(rider.last_name || '')}" required>
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderSuffix">Suffix</label>
                                        <input type="text" id="editRiderSuffix" value="${this.escAttr(rider.suffix || '')}" placeholder="Jr., Sr., III, etc.">
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderEmail" class="required">Email</label>
                                        <input type="email" id="editRiderEmail" value="${this.escAttr(rider.email || '')}" required>
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderPhone" class="required">Phone</label>
                                        <input type="tel" id="editRiderPhone" value="${this.escAttr(rider.phone_number || '')}" required>
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderGender" class="required">Gender</label>
                                        <select id="editRiderGender" required>
                                            <option value="Male" ${rider.gender === 'Male' ? 'selected' : ''}>Male</option>
                                            <option value="Female" ${rider.gender === 'Female' ? 'selected' : ''}>Female</option>
                                            <option value="Other" ${rider.gender === 'Other' ? 'selected' : ''}>Other</option>
                                        </select>
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderBirthDate" class="required">Birth Date</label>
                                        <input type="date" id="editRiderBirthDate" value="${birthDateStr}" required>
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderStatus" class="required">Status</label>
                                        <select id="editRiderStatus" required>
                                            <option value="active" ${rider.is_active === true ? 'selected' : ''}>Active</option>
                                            <option value="inactive" ${rider.is_active === false ? 'selected' : ''}>Inactive</option>
                                        </select>
                                    </div>
                                </div>
                            </div>

                            <div class="form-section">
                                <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                    <i class="fas fa-map-marker-alt"></i> Address
                                </h4>
                                <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
                                    <div class="form-field">
                                        <label for="editRiderStreet">Street</label>
                                        <input type="text" id="editRiderStreet" value="${this.escAttr(addressFields.street)}">
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderSitio">Sitio</label>
                                        <input type="text" id="editRiderSitio" value="${this.escAttr(addressFields.sitio)}">
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderBarangay" class="required">Barangay</label>
                                        ${barangaySelectHtml}
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderPostalCode">Postal Code</label>
                                        <input type="text" id="editRiderPostalCode" value="${this.escAttr(addressFields.postalCode)}">
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderCity" class="required">City</label>
                                        <input type="text" id="editRiderCity" value="${this.escAttr(addressFields.city)}" required readonly>
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderProvince" class="required">Province</label>
                                        <input type="text" id="editRiderProvince" value="${this.escAttr(addressFields.province)}" required readonly>
                                    </div>
                                </div>
                            </div>

                            <div class="form-section">
                                <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                    <i class="fas fa-id-card"></i> ID Information
                                </h4>
                                <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; margin-bottom: 20px;">
                                    <div class="form-field">
                                        <label for="editRiderIdType" class="required">ID Type</label>
                                        <select id="editRiderIdType" required>
                                            <option value="Philippine National ID" ${rider.id_type === 'Philippine National ID' ? 'selected' : ''}>Philippine National ID</option>
                                            <option value="Driver's License" ${rider.id_type === 'Driver\'s License' ? 'selected' : ''}>Driver's License</option>
                                            <option value="Philippine Passport" ${rider.id_type === 'Philippine Passport' ? 'selected' : ''}>Philippine Passport</option>
                                            <option value="SSS" ${rider.id_type === 'SSS' ? 'selected' : ''}>SSS</option>
                                            <option value="GSIS" ${rider.id_type === 'GSIS' ? 'selected' : ''}>GSIS</option>
                                            <option value="Other" ${rider.id_type === 'Other' ? 'selected' : ''}>Other</option>
                                        </select>
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderIdNumber" class="required">ID Number</label>
                                        <input type="text" id="editRiderIdNumber" value="${this.escAttr(rider.id_number || '')}" required>
                                    </div>
                                </div>
                                <p class="form-description" style="margin-bottom: 16px; color: #666; font-size: 14px;">Upload new photos only if you need to replace the existing ones.</p>
                                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
                                    <div class="form-field">
                                        <label for="editRiderIdFront">ID Front Photo</label>
                                        <input type="file" id="editRiderIdFront" accept="image/*">
                                        ${idFrontPreview}
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderIdBack">ID Back Photo</label>
                                        <input type="file" id="editRiderIdBack" accept="image/*">
                                        ${idBackPreview}
                                    </div>
                                </div>
                            </div>

                            <div class="form-section">
                                <h4 style="margin: 0 0 16px 0; font-size: 16px; font-weight: 600; color: #333; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px;">
                                    <i class="fas fa-motorcycle"></i> Vehicle Information
                                </h4>
                                <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px;">
                                    <div class="form-field">
                                        <label for="editRiderVehicleType" class="required">Vehicle Type</label>
                                        <select id="editRiderVehicleType" required>
                                            <option value="Motorcycle" ${rider.vehicle_type === 'Motorcycle' ? 'selected' : ''}>Motorcycle</option>
                                            <option value="Bicycle" ${rider.vehicle_type === 'Bicycle' ? 'selected' : ''}>Bicycle</option>
                                            <option value="Tricycle" ${rider.vehicle_type === 'Tricycle' ? 'selected' : ''}>Tricycle</option>
                                            <option value="Car" ${rider.vehicle_type === 'Car' ? 'selected' : ''}>Car</option>
                                            <option value="Van" ${rider.vehicle_type === 'Van' ? 'selected' : ''}>Van</option>
                                        </select>
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderVehicleNumber" class="required">Vehicle Plate Number</label>
                                        <input type="text" id="editRiderVehicleNumber" value="${this.escAttr(rider.vehicle_number || '')}" required>
                                    </div>
                                    <div class="form-field">
                                        <label for="editRiderLicenseNumber">Driver's License Number</label>
                                        <input type="text" id="editRiderLicenseNumber" value="${this.escAttr(rider.license_number || '')}">
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div class="form-actions" style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #e2e8f0; display: flex; gap: 12px; justify-content: flex-end;">
                            <button type="button" class="secondary-btn" onclick="adminManager.closeModal()">Cancel</button>
                            <button type="submit" class="primary-btn">
                                <i class="fas fa-save"></i> Save Changes
                            </button>
                        </div>
                    </form>
                </div>
            `;

            let modalOverlay = document.getElementById('adminModal');
            if (!modalOverlay) {
                modalOverlay = document.createElement('div');
                modalOverlay.id = 'adminModal';
                modalOverlay.className = 'modal-overlay scrollable-overlay';
                document.body.appendChild(modalOverlay);
            }
            modalOverlay.innerHTML = modalContent;
            modalOverlay.classList.add('show');
            modalOverlay.style.display = 'flex';

            modalOverlay.addEventListener('click', (e) => {
                if (e.target === modalOverlay) {
                    this.closeModal();
                }
            });

            const form = document.getElementById('editRiderForm');
            if (form) {
                form.addEventListener('submit', async (event) => {
                    event.preventDefault();
                    await this.updateRiderAccount(id);
                });
            }
        } catch (error) {
            console.error('Error opening edit rider modal:', error);
            alert('Failed to open rider editor: ' + error.message);
        }
    }

    async updateRiderAccount(id) {
        try {
            if (!id) {
                alert('Invalid rider record');
                return;
            }

            const supabase = typeof window.getSupabaseClient === 'function'
                ? window.getSupabaseClient()
                : (window.supabaseClient || null);

            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }

            const firstName = document.getElementById('editRiderFirstName')?.value.trim();
            const middleName = document.getElementById('editRiderMiddleName')?.value.trim();
            const lastName = document.getElementById('editRiderLastName')?.value.trim();
            const suffix = document.getElementById('editRiderSuffix')?.value.trim();
            const email = document.getElementById('editRiderEmail')?.value.trim();
            const phone = document.getElementById('editRiderPhone')?.value.trim();
            const gender = document.getElementById('editRiderGender')?.value.trim();
            const birthDate = document.getElementById('editRiderBirthDate')?.value;
            const status = document.getElementById('editRiderStatus')?.value.trim();
            const street = document.getElementById('editRiderStreet')?.value.trim();
            const sitio = document.getElementById('editRiderSitio')?.value.trim();
            const barangayField = document.getElementById('editRiderBarangay');
            const barangay = (barangayField?.tagName === 'SELECT') 
                ? barangayField.options[barangayField.selectedIndex]?.text 
                : barangayField?.value.trim();
            const postalCode = document.getElementById('editRiderPostalCode')?.value.trim();
            const city = document.getElementById('editRiderCity')?.value.trim() || 'Ormoc';
            const province = document.getElementById('editRiderProvince')?.value.trim() || 'Leyte';
            const idType = document.getElementById('editRiderIdType')?.value.trim();
            const idNumber = document.getElementById('editRiderIdNumber')?.value.trim();
            const vehicleType = document.getElementById('editRiderVehicleType')?.value.trim();
            const vehicleNumber = document.getElementById('editRiderVehicleNumber')?.value.trim();
            const licenseNumber = document.getElementById('editRiderLicenseNumber')?.value.trim();

            if (!firstName || !lastName || !email || !phone || !gender || !birthDate || 
                !barangay || !city || !province || !idType || !idNumber || 
                !vehicleType || !vehicleNumber) {
                alert('Please fill in all required fields');
                return;
            }

            const original = this._editingRiderOriginal || {};
            const changedFields = {};

            // Build full name
            let fullName = firstName;
            if (middleName) fullName += ' ' + middleName;
            fullName += ' ' + lastName;
            if (suffix) fullName += ' ' + suffix;

            // Build full address
            let fullAddressParts = [];
            if (street) fullAddressParts.push(street);
            if (sitio) fullAddressParts.push(`Sitio ${sitio}`);
            if (barangay) fullAddressParts.push(barangay);
            if (city) fullAddressParts.push(city);
            if (province) fullAddressParts.push(province);
            if (postalCode) fullAddressParts.push(postalCode);
            const fullAddress = fullAddressParts.length > 0 ? fullAddressParts.join(', ') : '';

            // Convert birth date to timestamp
            const birthDateTimestamp = birthDate ? new Date(birthDate).getTime() : null;

            // Check for changes
            if (firstName !== original.first_name) changedFields.first_name = firstName;
            if (middleName !== original.middle_name) changedFields.middle_name = middleName || null;
            if (lastName !== original.last_name) changedFields.last_name = lastName;
            if (suffix !== original.suffix) changedFields.suffix = suffix || null;
            if (fullName !== original.full_name) changedFields.full_name = fullName;
            if (email.toLowerCase() !== original.email) changedFields.email = email.toLowerCase();
            if (phone !== original.phone_number) changedFields.phone_number = phone;
            if (gender !== original.gender) changedFields.gender = gender;
            if (birthDateTimestamp !== original.birth_date) changedFields.birth_date = birthDateTimestamp;
            if (street !== original.street) changedFields.street = street || null;
            if (sitio !== original.sitio) changedFields.sitio = sitio || null;
            if (barangay !== original.barangay) changedFields.barangay = barangay;
            if (postalCode !== original.postal_code) changedFields.postal_code = postalCode || null;
            if (city !== original.city) changedFields.city = city;
            if (province !== original.province) changedFields.province = province;
            if (fullAddress !== original.address) changedFields.address = fullAddress;
            if (idType !== original.id_type) changedFields.id_type = idType;
            if (idNumber !== original.id_number) changedFields.id_number = idNumber;
            if (vehicleType !== original.vehicle_type) changedFields.vehicle_type = vehicleType;
            if (vehicleNumber !== original.vehicle_number) changedFields.vehicle_number = vehicleNumber;
            if (licenseNumber !== original.license_number) changedFields.license_number = licenseNumber || null;

            const isActive = status === 'active';
            if (isActive !== original.is_active) changedFields.is_active = isActive;

            const submitBtn = document.querySelector('#editRiderForm button[type="submit"]');
            if (submitBtn) {
                submitBtn.disabled = true;
                submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
            }

            // Handle ID photo uploads
            const newIdFrontFile = document.getElementById('editRiderIdFront')?.files?.[0] || null;
            const newIdBackFile = document.getElementById('editRiderIdBack')?.files?.[0] || null;

            if (newIdFrontFile || newIdBackFile) {
                try {
                    if (window.FirebaseUtils && typeof window.FirebaseUtils.uploadStaffIdPhoto === 'function') {
                        if (newIdFrontFile) {
                            const frontUrl = await window.FirebaseUtils.uploadStaffIdPhoto(newIdFrontFile, id, 'front');
                            changedFields.id_front_photo = frontUrl;
                        }
                        if (newIdBackFile) {
                            const backUrl = await window.FirebaseUtils.uploadStaffIdPhoto(newIdBackFile, id, 'back');
                            changedFields.id_back_photo = backUrl;
                        }
                    } else {
                        throw new Error('Photo upload utility not available');
                    }
                } catch (uploadError) {
                    console.error('Error uploading ID photos:', uploadError);
                    if (submitBtn) {
                        submitBtn.disabled = false;
                        submitBtn.innerHTML = '<i class="fas fa-save"></i> Save Changes';
                    }
                    alert('Error uploading ID photos: ' + uploadError.message);
                    return;
                }
            }

            if (Object.keys(changedFields).length === 0) {
                alert('No changes detected');
                if (submitBtn) {
                    submitBtn.disabled = false;
                    submitBtn.innerHTML = '<i class="fas fa-save"></i> Save Changes';
                }
                return;
            }

            // Stamp last update time
            changedFields.updated_at = Date.now();

            // Update rider in Supabase
            const { error: updateError } = await supabase
                .from('riders')
                .update(changedFields)
                .eq('uid', id);

            if (updateError) {
                throw new Error('Failed to update rider: ' + updateError.message);
            }

            if (submitBtn) {
                submitBtn.disabled = false;
                submitBtn.innerHTML = '<i class="fas fa-save"></i> Save Changes';
            }

            this.closeModal();
            this.showSuccessMessage('Rider account updated successfully');
            
            // Refresh rider list if staffManager exists
            if (window.staffManager && typeof window.staffManager.loadRidersManagementData === 'function') {
                window.staffManager.loadRidersManagementData();
            }

        } catch (error) {
            console.error('Error updating rider account:', error);
            const submitBtn = document.querySelector('#editRiderForm button[type="submit"]');
            if (submitBtn) {
                submitBtn.disabled = false;
                submitBtn.innerHTML = '<i class="fas fa-save"></i> Save Changes';
            }
            alert('Error updating rider account: ' + error.message);
        }
    }

    async removeRider(id) {
        try {
            if (!confirm('Are you sure you want to permanently delete this rider? This action cannot be undone.')) {
                return;
            }

            // Get Supabase client
            let supabase = null;
            if (typeof window.getSupabaseClient === 'function') {
                supabase = window.getSupabaseClient();
            } else if (window.supabaseClient) {
                supabase = window.supabaseClient;
            }
            
            if (!supabase) {
                alert('Supabase client not initialized. Please refresh the page.');
                return;
            }

            const { error: deleteError } = await supabase
                .from('riders')
                .delete()
                .eq('uid', id);

            if (deleteError) {
                throw new Error(deleteError.message);
            }

            this.showSuccessMessage('Rider removed successfully');
            
            // Refresh rider list if staffManager exists
            if (window.staffManager && typeof window.staffManager.loadRidersManagementData === 'function') {
                window.staffManager.loadRidersManagementData();
            }
        } catch (error) {
            console.error('Error removing rider:', error);
            alert('Error removing rider: ' + error.message);
        }
    }
}

// Initialize Admin Manager
const adminManager = new AdminManager();

// Make it globally available
window.adminManager = adminManager;

// Initialize when DOM is loaded
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        adminManager.initialize();
    });
} else {
    adminManager.initialize();
}

