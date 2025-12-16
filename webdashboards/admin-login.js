// Admin Login Manager
class AdminLoginManager {
  constructor() {
    this.selectedRole = "admin"; // Default to admin since it's pre-selected in HTML
  }

  // Check if error is network-related
  isNetworkError(error) {
    if (!error) return false;

    const errorMessage = String(error.message || error).toLowerCase();
    const errorCode = error.code || error.status || error.statusCode;

    // Check for common network error indicators
    const networkErrorPatterns = [
      "network error",
      "failed to fetch",
      "network request failed",
      "internet connection",
      "no internet",
      "offline",
      "timeout",
      "connection refused",
      "connection reset",
      "connection closed",
      "econnrefused",
      "enotfound",
      "etimedout",
      "econnreset",
      "typeerror: failed to fetch",
    ];

    // Check error message
    if (
      networkErrorPatterns.some((pattern) => errorMessage.includes(pattern))
    ) {
      return true;
    }

    // Check for fetch API network errors
    if (error instanceof TypeError && errorMessage.includes("fetch")) {
      return true;
    }

    // Check for HTTP status codes that indicate network issues
    if (
      errorCode === 0 ||
      errorCode === 408 ||
      errorCode === 504 ||
      errorCode === 503
    ) {
      return true;
    }

    // Check if navigator.onLine is false
    if (typeof navigator !== "undefined" && navigator.onLine === false) {
      return true;
    }

    // Check for Supabase network errors
    if (
      error.message &&
      (error.message.includes("Failed to fetch") ||
        error.message.includes("NetworkError") ||
        error.message.includes("Network request failed"))
    ) {
      return true;
    }

    return false;
  }

  initialize() {
    // Set up login form
    this.setupLoginForm();

    // Set up role button selection
    this.setupRoleSelection();
  }

  setupLoginForm() {
    const loginForm = document.getElementById("adminLoginForm");
    if (loginForm) {
      loginForm.addEventListener("submit", (e) => {
        e.preventDefault();
        this.handleLogin();
      });
    }
  }

  setupRoleSelection() {
    const roleButtons = document.querySelectorAll(".role-btn");
    roleButtons.forEach((button) => {
      button.addEventListener("click", () => {
        // Remove selected class from all buttons
        roleButtons.forEach((btn) => btn.classList.remove("selected"));

        // Add selected class to clicked button
        button.classList.add("selected");

        // Store selected role
        this.selectedRole = button.dataset.role;

        // Clear any existing error messages when switching roles
        this.clearLoginError();

        // Show login form
        const loginForm = document.getElementById("adminLoginForm");
        loginForm.classList.remove("hidden");

        // Show role info
        this.showRoleInfo(this.selectedRole);
      });
    });
  }

  showRoleInfo(role) {
    const roleInfo = document.querySelector(".role-info");
    if (roleInfo) {
      roleInfo.remove();
    }

    // Role info removed - no longer showing credentials
  }

  async handleLogin() {
    const email = document.getElementById("adminEmail").value.trim();
    const password = document.getElementById("adminPassword").value;
    const errorDiv = document.getElementById("loginError");

    // Clear previous error
    errorDiv.style.display = "none";
    errorDiv.textContent = "";

    if (!email || !password || !this.selectedRole) {
      this.showLoginError("Please fill in all fields and select a role");
      return;
    }

    try {
      // Set loading state
      this.setLoadingState(true);

      if (this.selectedRole === "admin") {
        await this.authenticateAdmin(email, password);
      } else if (this.selectedRole === "staff") {
        await this.authenticateStaff(email, password);
      }
    } catch (error) {
      // Check if it's a network error
      if (this.isNetworkError(error)) {
        this.showLoginError(
          "Login failed. Check your internet connection and try again."
        );
      } else {
        // Show original error message for non-network errors
        this.showLoginError(error.message);
      }
    } finally {
      // Clear loading state
      this.setLoadingState(false);
    }
  }

  async authenticateAdmin(email, password) {
    try {
      console.log("Attempting Supabase authentication for admin:", email);

      // Get Supabase client
      const supabase = getSupabaseClient();
      if (!supabase) {
        throw new Error(
          "Supabase client not initialized. Please refresh the page."
        );
      }

      // Check if offline before attempting authentication
      if (typeof navigator !== "undefined" && navigator.onLine === false) {
        throw new Error("Network error: No internet connection");
      }

      const lowerEmail = email.toLowerCase();

      // STEP 1: Use Supabase Auth as the source of truth for admin email/password.
      // This ensures we work with hashed passwords and proper auth flows.
      let authData = null;
      try {
        const signInResult = await supabase.auth.signInWithPassword({
          email: lowerEmail,
          password,
        });

        authData = signInResult.data;

        if (signInResult.error) {
          const msg = (signInResult.error.message || "").toLowerCase();
          console.error(
            "Supabase Auth sign-in error for admin:",
            signInResult.error
          );

          if (
            msg.includes("email") &&
            (msg.includes("confirm") || msg.includes("verification"))
          ) {
            throw new Error(
              "Please confirm your admin email address before logging in."
            );
          }

          throw new Error("Invalid admin credentials");
        }
      } catch (authException) {
        if (this.isNetworkError(authException)) {
          throw new Error("Network error: Failed to reach authentication server");
        }
        if (authException instanceof Error) {
          throw authException;
        }
        console.error(
          "Unexpected error during admin Auth sign-in:",
          authException
        );
        throw new Error("Authentication failed while verifying your account.");
      }

      const authUser = authData && authData.user ? authData.user : null;

      // Optional: log confirmation status for debugging
      if (authUser) {
        console.log("Admin auth user:", {
          email: authUser.email,
          email_confirmed_at: authUser.email_confirmed_at,
        });
      }

      // STEP 2: Load admin profile from admins table (metadata, status, etc.)
      // Query admin by email with timeout handling
      let queryResult;
      try {
        queryResult = await Promise.race([
          supabase
            .from("admins")
            .select("*")
            .eq("email", lowerEmail)
            .limit(1),
          new Promise((_, reject) =>
            setTimeout(
              () => reject(new Error("Network error: Request timeout")),
              30000
            )
          ),
        ]);
      } catch (timeoutError) {
        // Check if it's a timeout or network error
        if (
          this.isNetworkError(timeoutError) ||
          timeoutError.message.includes("timeout")
        ) {
          throw new Error("Network error: Failed to fetch");
        }
        throw timeoutError;
      }

      const { data: admins, error: queryError } = queryResult;

      if (queryError) {
        console.error("Supabase query error:", queryError);
        // Check if it's a network error
        if (this.isNetworkError(queryError)) {
          throw new Error("Network error: Failed to fetch");
        }
        throw new Error("Database error: " + queryError.message);
      }

      if (!admins || admins.length === 0) {
        throw new Error("Invalid admin credentials");
      }

      const admin = admins[0];

      // Check account status
      if (admin.status !== "active") {
        throw new Error(
          "Your admin account is deactivated. Please contact support."
        );
      }

      // Update last_login and last_seen timestamps
      const now = new Date().toISOString();
      const { error: updateError } = await supabase
        .from("admins")
        .update({
          last_login: now,
          last_seen: now,
          updated_at: now,
        })
        .eq("uuid", admin.uuid);

      if (updateError) {
        console.warn("Failed to update last_login/last_seen:", updateError);
        // Don't throw error - login should still proceed
      }

      // Prepare user data (using uuid as the identifier)
      const userData = {
        uid: admin.uuid,
        role: "admin",
        name: admin.fullname || admin.username || "Administrator",
        email: admin.email,
      };

      // Store session data
      sessionStorage.setItem("adminUid", userData.uid);
      sessionStorage.setItem("adminRole", userData.role);
      sessionStorage.setItem("adminName", userData.name);
      sessionStorage.setItem("userRole", "admin");
      sessionStorage.setItem("username", userData.name);
      sessionStorage.setItem("userEmail", userData.email);
      sessionStorage.setItem("authMethod", "supabase");

      console.log("✅ Admin authentication successful:", userData);

      // Show loading message and wait 2 seconds before redirect
      const loadingMessage = document.createElement("div");
      loadingMessage.id = "loginLoadingMessage";
      loadingMessage.style.cssText =
        "position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: linear-gradient(135deg, #10b981 0%, #059669 100%); display: flex; align-items: center; justify-content: center; z-index: 10000; color: white; font-size: 18px; font-weight: 600; font-family: Inter, sans-serif;";
      loadingMessage.innerHTML =
        '<div style="text-align: center;"><div style="margin-bottom: 16px;"><i class="fas fa-spinner fa-spin" style="font-size: 48px;"></i></div><div>Loading dashboard...</div></div>';
      document.body.appendChild(loadingMessage);

      // Redirect to unified dashboard (staff-dashboard.html) after 2 seconds
      const redirectUrl = `staff-dashboard.html?uid=${encodeURIComponent(
        userData.uid
      )}&role=admin&username=${encodeURIComponent(
        userData.name
      )}&email=${encodeURIComponent(userData.email)}`;
      setTimeout(() => {
        window.location.href = redirectUrl;
      }, 2000);
    } catch (error) {
      console.error("❌ Admin authentication error:", error);
      // If it's already a network error, re-throw it as-is so it gets caught by handleLogin
      if (this.isNetworkError(error)) {
        throw error;
      }
      throw new Error(
        "Authentication failed: " +
          (error && error.message ? error.message : "Unexpected error")
      );
    }
  }

  async authenticateStaff(email, password) {
    try {
      console.log("Attempting Supabase authentication for staff:", email);

      // Check if offline before attempting authentication
      if (typeof navigator !== "undefined" && navigator.onLine === false) {
        throw new Error("Network error: No internet connection");
      }

      const supabase = getSupabaseClient();
      if (!supabase) {
        throw new Error(
          "Supabase client not initialized. Please refresh the page."
        );
      }

      const lowerEmail = email.toLowerCase();

      // STEP 2–5A: Use Supabase Auth as source of truth for email/password/confirmation.
      // 1) Try signInWithPassword.
      // 2) If user not found → signUp + confirmation email + create staff row, then block login.
      // 3) If email not confirmed → block login.
      // 4) If sign-in succeeds and email is confirmed → continue to staff table check.
      let authData = null;
      try {
        const signInResult = await supabase.auth.signInWithPassword({
          email: lowerEmail,
          password,
        });

        authData = signInResult.data;

        if (signInResult.error) {
          const msg = (signInResult.error.message || "").toLowerCase();

          // Email exists but not yet confirmed
          if (msg.includes("email") && msg.includes("confirm")) {
            throw new Error(
              "Please confirm your email address from the confirmation link we sent you before logging in."
            );
          }

          // User not found (or generic invalid credentials for a non-existing user)
          // → create auth user & staff record, then block login until confirmed.
          // Supabase often returns "Invalid login credentials" for both wrong password
          // and non-existing users, so we optimistically try signUp here and rely on
          // the "already registered" error to distinguish existing accounts.
          if (
            msg.includes("user not found") ||
            msg.includes("invalid login credentials")
          ) {
            const { error: signUpError } = await supabase.auth.signUp({
              email: lowerEmail,
              password,
              options: {
                emailRedirectTo: window.location.origin + "/index.html",
              },
            });

            if (signUpError) {
              const signUpMsg = (signUpError.message || "").toLowerCase();
              if (
                signUpMsg.includes("already registered") ||
                signUpMsg.includes("user already registered") ||
                signUpMsg.includes("user already exists")
              ) {
                // Edge case: Auth says user not found but signUp says exists – treat as invalid credentials.
                throw new Error("Invalid staff credentials");
              }
              console.error(
                "Supabase Auth sign-up error for staff:",
                signUpError
              );
              throw new Error(
                "Authentication failed: " +
                  (signUpError.message ||
                    "Unexpected error during account creation")
              );
            }

            // Also create staff row (if not already present)
            try {
              await supabase.from("staff").insert({
                email: lowerEmail,
                password: password,
                status: "active",
              });
            } catch (insertError) {
              console.warn(
                "Staff insert during signup failed (may already exist):",
                insertError
              );
            }

            throw new Error(
              "We have sent a confirmation email to your address. Please confirm your account before logging in."
            );
          }

          // Any other auth error → invalid credentials
          console.error(
            "Supabase Auth sign-in error for staff:",
            signInResult.error
          );
          throw new Error("Invalid staff credentials");
        }
      } catch (authException) {
        if (authException instanceof Error) {
          // Controlled messages (like confirmation required) bubble up.
          throw authException;
        }
        console.error(
          "Unexpected error during staff Auth sign-in:",
          authException
        );
        throw new Error("Authentication failed while verifying your account.");
      }

      const authUser = authData && authData.user ? authData.user : null;

      // CRITICAL: Check if email is confirmed
      // Supabase uses email_confirmed_at (timestamp) or confirmed_at (boolean) depending on version
      // If signInWithPassword succeeded, we should check the actual confirmation status
      if (authUser) {
        const isEmailConfirmed =
          authUser.email_confirmed_at !== null &&
          authUser.email_confirmed_at !== undefined &&
          authUser.email_confirmed_at !== "";

        console.log("Email confirmation check:", {
          email: authUser.email,
          email_confirmed_at: authUser.email_confirmed_at,
          confirmed_at: authUser.confirmed_at,
          isEmailConfirmed: isEmailConfirmed,
        });

        if (!isEmailConfirmed) {
          // Email not confirmed - try to resend confirmation email
          try {
            await supabase.auth.resend({
              type: "signup",
              email: lowerEmail,
            });
          } catch (resendError) {
            console.warn("Failed to resend confirmation email:", resendError);
          }

          throw new Error(
            "Please confirm your email address from the confirmation link we sent you before logging in."
          );
        }

        console.log("✅ Email is confirmed, proceeding with staff table check");
      }

      // STEP 5B: Check the Staff table after Auth has succeeded.
      let staffRecord = null;
      try {
        const staffResult = await Promise.race([
          supabase.from("staff").select("*").eq("email", lowerEmail).limit(1),
          new Promise((_, reject) =>
            setTimeout(
              () => reject(new Error("Network error: Request timeout")),
              30000
            )
          ),
        ]);

        const { data: staffMembers, error: staffError } = staffResult;
        if (staffError) {
          console.error("Supabase staff query error:", staffError);
          if (this.isNetworkError(staffError)) {
            throw new Error("Network error: Failed to fetch");
          }
          throw new Error("Database error: " + staffError.message);
        }

        if (staffMembers && staffMembers.length > 0) {
          staffRecord = staffMembers[0];
        }
      } catch (staffTimeoutError) {
        if (
          this.isNetworkError(staffTimeoutError) ||
          staffTimeoutError.message.includes("timeout")
        ) {
          throw new Error("Network error: Failed to fetch");
        }
        throw staffTimeoutError;
      }

      // If no staff record exists yet (e.g., legacy accounts), create one now.
      if (!staffRecord) {
        try {
          const { data: newStaff, error: insertError } = await supabase
            .from("staff")
            .insert({
              email: lowerEmail,
              password: password,
              status: "active",
            })
            .select()
            .limit(1);

          if (insertError) {
            console.error(
              "Staff insert after Auth success failed:",
              insertError
            );
            // Don't block login entirely if staff table insert fails; show generic error.
            throw new Error(
              "Your staff account could not be created correctly. Please contact the administrator."
            );
          }

          staffRecord = newStaff && newStaff.length > 0 ? newStaff[0] : null;
        } catch (insertException) {
          if (insertException instanceof Error) {
            throw insertException;
          }
          console.error(
            "Unexpected error inserting staff record:",
            insertException
          );
          throw new Error(
            "Your staff account could not be created correctly. Please contact the administrator."
          );
        }
      }

      if (!staffRecord) {
        throw new Error(
          "Your staff account could not be located. Please contact the administrator."
        );
      }

      if (staffRecord.status !== "active") {
        throw new Error(
          "Your staff account is deactivated. Please contact the admin."
        );
      }

      // Prepare user data (using uuid as the identifier)
      const userData = {
        uid: staffRecord.uuid,
        role: "staff",
        name: staffRecord.full_name || staffRecord.fullName || "Staff Member",
        email: staffRecord.email,
      };

      // Store session data
      sessionStorage.setItem("staffUid", userData.uid);
      sessionStorage.setItem("staffRole", userData.role);
      sessionStorage.setItem("staffName", userData.name);
      sessionStorage.setItem("userRole", "staff");
      sessionStorage.setItem("username", userData.name);
      sessionStorage.setItem("userEmail", userData.email);
      sessionStorage.setItem("authMethod", "supabase");

      console.log("✅ Staff authentication successful:", userData);

      // Show loading message and wait 2 seconds before redirect
      const loadingMessage = document.createElement("div");
      loadingMessage.id = "loginLoadingMessage";
      loadingMessage.style.cssText =
        "position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: linear-gradient(135deg, #10b981 0%, #059669 100%); display: flex; align-items: center; justify-content: center; z-index: 10000; color: white; font-size: 18px; font-weight: 600; font-family: Inter, sans-serif;";
      loadingMessage.innerHTML =
        '<div style="text-align: center;"><div style="margin-bottom: 16px;"><i class="fas fa-spinner fa-spin" style="font-size: 48px;"></i></div><div>Loading dashboard...</div></div>';
      document.body.appendChild(loadingMessage);

      // Redirect to unified dashboard (staff-dashboard.html) after 2 seconds
      // Parameters will be stored in sessionStorage and URL will be cleaned automatically
      const redirectUrl = `staff-dashboard.html?uid=${encodeURIComponent(
        userData.uid
      )}&role=staff&username=${encodeURIComponent(
        userData.name
      )}&email=${encodeURIComponent(userData.email)}`;
      setTimeout(() => {
        window.location.href = redirectUrl;
      }, 2000);
    } catch (error) {
      console.error("❌ Staff authentication error:", error);
      // If it's already a network error, re-throw it as-is so it gets caught by handleLogin
      if (this.isNetworkError(error)) {
        throw error;
      }
      throw new Error(
        "Authentication failed: " +
          (error && error.message ? error.message : "Unexpected error")
      );
    }
  }

  showLoginError(message) {
    const errorDiv = document.getElementById("loginError");
    errorDiv.textContent = message;
    errorDiv.style.display = "block";
  }

  clearLoginError() {
    const errorDiv = document.getElementById("loginError");
    errorDiv.textContent = "";
    errorDiv.style.display = "none";

    // Also clear the form fields when switching roles
    const emailField = document.getElementById("adminEmail");
    const passwordField = document.getElementById("adminPassword");

    if (emailField) emailField.value = "";
    if (passwordField) passwordField.value = "";

    // Remove any validation error states
    const emailGroup = document.getElementById("emailGroup");
    const passwordGroup = passwordField
      ? passwordField.closest(".form-group")
      : null;

    if (emailGroup) emailGroup.classList.remove("invalid");
    if (passwordGroup) passwordGroup.classList.remove("invalid");
  }

  setLoadingState(isLoading) {
    const loginBtn = document.querySelector(".login-btn");
    const emailField = document.getElementById("adminEmail");
    const passwordField = document.getElementById("adminPassword");

    if (isLoading) {
      // Set loading state
      loginBtn.disabled = true;
      loginBtn.setAttribute("aria-busy", "true");
      loginBtn.innerHTML =
        '<i class="fas fa-spinner fa-spin"></i> Logging in...';

      // Disable form fields
      if (emailField) emailField.disabled = true;
      if (passwordField) passwordField.disabled = true;

      // Disable role buttons
      const roleButtons = document.querySelectorAll(".role-btn");
      roleButtons.forEach((btn) => (btn.disabled = true));
    } else {
      // Clear loading state
      loginBtn.disabled = false;
      loginBtn.removeAttribute("aria-busy");
      loginBtn.innerHTML = '<i class="fas fa-sign-in-alt"></i> Login';

      // Re-enable form fields
      if (emailField) emailField.disabled = false;
      if (passwordField) passwordField.disabled = false;

      // Re-enable role buttons
      const roleButtons = document.querySelectorAll(".role-btn");
      roleButtons.forEach((btn) => (btn.disabled = false));
    }
  }
}

// Initialize Login Manager
const loginManager = new AdminLoginManager();

// Initialize when DOM is loaded
document.addEventListener("DOMContentLoaded", () => {
  loginManager.initialize();
});
