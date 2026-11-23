package com.physical_treatment_and_health_support_system.tarumt.physical_treatment_and_health_support_system

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Per-account watch connection. The PIN is encrypted with an app-owned Android Keystore key. */
class WatchConnectionStore(context: Context) {
    private val prefs = context.getSharedPreferences("watch_connections", Context.MODE_PRIVATE)
    private val alias = "healthguide_watch_connections"

    private fun accountKey(account: String): String {
        require(account.isNotBlank() && account.length <= 100)
        return MessageDigest.getInstance("SHA-256").digest(account.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build())
        }.generateKey()
    }

    fun read(account: String): JSONObject? {
        val encoded = prefs.getString(accountKey(account), null) ?: return null
        val parts = encoded.split(":")
        require(parts.size == 2)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
        return JSONObject(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
    }

    fun save(account: String, connection: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val data = cipher.doFinal(connection.toString().toByteArray(Charsets.UTF_8))
        val encoded = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(data, Base64.NO_WRAP)
        check(prefs.edit().putString(accountKey(account), encoded).commit())
    }

    fun forget(account: String) {
        check(prefs.edit().remove(accountKey(account)).commit())
    }
}
