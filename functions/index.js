const {setGlobalOptions} = require("firebase-functions");
const {onCall, HttpsError} = require("firebase-functions/https");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

initializeApp();

setGlobalOptions({
  maxInstances: 10,
});

// =====================================================
// ADMIN CHECK
// =====================================================

async function checkAdmin(request) {
  if (!request.auth) {
    throw new HttpsError(
        "unauthenticated",
        "You must be logged in.",
    );
  }

  const db = getFirestore();

  const adminDoc = await db
      .collection("users")
      .doc(request.auth.uid)
      .get();

  if (!adminDoc.exists) {
    throw new HttpsError(
        "permission-denied",
        "Admin profile not found.",
    );
  }

  const adminData = adminDoc.data();

  if (adminData.role !== "admin") {
    throw new HttpsError(
        "permission-denied",
        "Only Admin can perform this action.",
    );
  }

  return request.auth.uid;
}

// =====================================================
// TEST FUNCTION
// =====================================================

exports.testFunction = onCall((request) => {
  logger.info("Staff function is working.");

  return {
    success: true,
    message: "Staff Function is working!",
  };
});

// =====================================================
// CREATE NEW STAFF
// =====================================================

exports.createStaff = onCall(async (request) => {
  const adminUid = await checkAdmin(request);

  const db = getFirestore();
  const auth = getAuth();

  const data = request.data || {};

  const name = typeof data.name === "string"
      ? data.name.trim()
      : "";

  const email = typeof data.email === "string"
      ? data.email.trim().toLowerCase()
      : "";

  const password = typeof data.password === "string"
      ? data.password
      : "";

  const role = typeof data.role === "string"
      ? data.role.trim().toLowerCase()
      : "staff";

  const active = typeof data.active === "boolean"
      ? data.active
      : true;

  if (!name || !email || !password) {
    throw new HttpsError(
        "invalid-argument",
        "Name, email and password are required.",
    );
  }

  if (password.length < 6) {
    throw new HttpsError(
        "invalid-argument",
        "Password must be at least 6 characters.",
    );
  }

  if (role !== "staff" && role !== "manager") {
    throw new HttpsError(
        "invalid-argument",
        "Role must be Staff or Manager.",
    );
  }

  if (!email.includes("@")) {
    throw new HttpsError(
        "invalid-argument",
        "Please enter a valid email address.",
    );
  }

  let staffUser = null;

  try {
    staffUser = await auth.createUser({
      email: email,
      password: password,
      displayName: name,
      disabled: !active,
    });

    await db
        .collection("users")
        .doc(staffUser.uid)
        .set({
          uid: staffUser.uid,
          name: name,
          email: email,
          role: role,
          active: active,
          createdBy: adminUid,
          createdAt: Timestamp.now(),
        });

    logger.info("Staff account created.", {
      uid: staffUser.uid,
      email: email,
      role: role,
    });

    return {
      success: true,
      message: "Staff created successfully.",
      uid: staffUser.uid,
      name: name,
      email: email,
      role: role,
      active: active,
    };
  } catch (error) {
    logger.error("Error creating staff.", error);

    if (staffUser) {
      try {
        await auth.deleteUser(staffUser.uid);
      } catch (deleteError) {
        logger.error(
            "Could not clean up Authentication user.",
            deleteError,
        );
      }
    }

    if (error.code === "auth/email-already-exists") {
      throw new HttpsError(
          "already-exists",
          "A staff account with this email already exists.",
      );
    }

    if (error.code === "auth/invalid-email") {
      throw new HttpsError(
          "invalid-argument",
          "Please enter a valid email address.",
      );
    }

    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError(
        "internal",
        error.message || "Unable to create staff.",
    );
  }
});

// =====================================================
// UPDATE STAFF
// =====================================================

exports.updateStaff = onCall(async (request) => {
  await checkAdmin(request);

  const db = getFirestore();
  const auth = getAuth();

  const data = request.data || {};

  const uid = typeof data.uid === "string"
      ? data.uid.trim()
      : "";

  const name = typeof data.name === "string"
      ? data.name.trim()
      : "";

  const role = typeof data.role === "string"
      ? data.role.trim().toLowerCase()
      : "";

  if (!uid || !name || !role) {
    throw new HttpsError(
        "invalid-argument",
        "UID, name and role are required.",
    );
  }

  if (role !== "staff" && role !== "manager") {
    throw new HttpsError(
        "invalid-argument",
        "Role must be Staff or Manager.",
    );
  }

  try {
    await auth.updateUser(uid, {
      displayName: name,
    });

    await db
        .collection("users")
        .doc(uid)
        .update({
          name: name,
          role: role,
          updatedAt: Timestamp.now(),
        });

    return {
      success: true,
      message: "Staff updated successfully.",
    };
  } catch (error) {
    logger.error("Error updating staff.", error);

    if (error.code === "auth/user-not-found") {
      throw new HttpsError(
          "not-found",
          "Staff authentication account not found.",
      );
    }

    throw new HttpsError(
        "internal",
        error.message || "Unable to update staff.",
    );
  }
});

// =====================================================
// ACTIVATE / DEACTIVATE STAFF
// =====================================================

exports.setStaffStatus = onCall(async (request) => {
  await checkAdmin(request);

  const db = getFirestore();
  const auth = getAuth();

  const data = request.data || {};

  const uid = typeof data.uid === "string"
      ? data.uid.trim()
      : "";

  const active = data.active === true;

  if (!uid) {
    throw new HttpsError(
        "invalid-argument",
        "Staff UID is required.",
    );
  }

  try {
    await auth.updateUser(uid, {
      disabled: !active,
    });

    await db
        .collection("users")
        .doc(uid)
        .update({
          active: active,
          updatedAt: Timestamp.now(),
        });

    return {
      success: true,
      active: active,
      message: active
          ? "Staff activated successfully."
          : "Staff deactivated successfully.",
    };
  } catch (error) {
    logger.error("Error changing staff status.", error);

    if (error.code === "auth/user-not-found") {
      throw new HttpsError(
          "not-found",
          "Staff authentication account not found.",
      );
    }

    throw new HttpsError(
        "internal",
        error.message || "Unable to change staff status.",
    );
  }
});

// =====================================================
// DELETE STAFF
// =====================================================

exports.deleteStaff = onCall(async (request) => {
  await checkAdmin(request);

  const db = getFirestore();
  const auth = getAuth();

  const data = request.data || {};

  const uid = typeof data.uid === "string"
      ? data.uid.trim()
      : "";

  if (!uid) {
    throw new HttpsError(
        "invalid-argument",
        "Staff UID is required.",
    );
  }

  try {
    // Delete Firebase Authentication account.
    try {
      await auth.deleteUser(uid);
    } catch (authError) {
      if (authError.code !== "auth/user-not-found") {
        throw authError;
      }
    }

    // Delete Firestore profile.
    await db
        .collection("users")
        .doc(uid)
        .delete();

    // Delete chat messages.
    const chatsSnapshot = await db
        .collection("chats")
        .where("staffId", "==", uid)
        .get();

    for (const chatDoc of chatsSnapshot.docs) {
      const messagesSnapshot = await chatDoc.ref
          .collection("messages")
          .get();

      const batch = db.batch();

      for (const messageDoc of messagesSnapshot.docs) {
        batch.delete(messageDoc.ref);
      }

      batch.delete(chatDoc.ref);

      await batch.commit();
    }

    logger.info("Staff deleted.", {
      uid: uid,
    });

    return {
      success: true,
      message: "Staff deleted successfully.",
    };
  } catch (error) {
    logger.error("Error deleting staff.", error);

    throw new HttpsError(
        "internal",
        error.message || "Unable to delete staff.",
    );
  }
});