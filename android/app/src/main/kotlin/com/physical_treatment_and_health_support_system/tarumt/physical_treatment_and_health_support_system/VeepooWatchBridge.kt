package com.physical_treatment_and_health_support_system.tarumt.physical_treatment_and_health_support_system

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.format.DateFormat
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.inuker.bluetooth.library.Code
import com.inuker.bluetooth.library.search.SearchResult
import com.inuker.bluetooth.library.search.response.SearchResponse
import com.veepoo.protocol.VPOperateManager
import com.veepoo.protocol.listener.base.IBleWriteResponse
import com.veepoo.protocol.listener.data.*
import com.veepoo.protocol.model.datas.*
import com.veepoo.protocol.model.enums.DeviceManualDataType
import com.veepoo.protocol.model.enums.EPwdStatus
import com.veepoo.protocol.shareprence.VpSpGetUtil
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.time.ZoneId
import org.json.JSONObject

/** One bounded scan or read at a time. Device records are returned for review before saving. */
class VeepooWatchBridge(private val activity: FlutterFragmentActivity) : MethodChannel.MethodCallHandler {
    private val handler = Handler(Looper.getMainLooper())
    private val manager get() = VPOperateManager.getInstance()
    private var pending: MethodChannel.Result? = null
    private var permissionAction: (() -> Unit)? = null
    private var generation = 0
    private var scanning = false
    private var initialized = false
    private var reading = false
    private var watchDays = 3
    private val connections = WatchConnectionStore(activity)
    private var activeAccount: String? = null
    private val permissions = activity.registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        val action = permissionAction
        permissionAction = null
        if (hasPermissions()) action?.invoke()
        else fail("permission", "Allow Nearby devices access to find and read your watch.")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") {
            close()
            result.success(null)
            return
        }
        if (call.method in listOf("connection", "remember", "markSynced", "forget")) {
            connectionSetting(call, result)
            return
        }
        if (call.method !in listOf("scan", "readBloodPressure", "readHistory", "readConnected")) {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("busy", "A watch operation is already running.", null)
            return
        }
        pending = result
        generation++
        activeAccount = call.argument<String>("accountId")
        val action = {
            try {
                val bluetooth = activity.getSystemService(BluetoothManager::class.java).adapter
                if (bluetooth?.isEnabled != true) {
                    fail("bluetooth_off", "Turn on Bluetooth, then try again.")
                } else if (call.method == "scan") {
                    scan()
                } else {
                    if (call.method == "readConnected") {
                        val saved = connections.read(activeAccount!!)
                        if (saved == null) fail("not_connected", "Connect your watch to enable automatic syncing.")
                        else read(MethodCall("readHistory", mapOf(
                            "address" to saved.getString("address"),
                            "name" to saved.getString("name"),
                            "pin" to saved.getString("pin")
                        )))
                    } else read(call)
                }
            } catch (_: SecurityException) {
                fail("permission", "Allow Nearby devices access in your phone's app settings.")
            } catch (_: Exception) {
                fail("watch_error", "The watch could not be read. Disconnect it from its companion app first, then try Bluetooth again.")
            } catch (_: LinkageError) {
                fail("sdk_error", "The watch integration could not start on this device.")
            }
        }
        if (hasPermissions()) action() else if (call.method == "readConnected") {
            fail("permission", "Allow Nearby devices access, then reconnect your watch.")
        } else {
            permissionAction = action
            permissions.launch(requiredPermissions())
        }
    }

    private fun connectionSetting(call: MethodCall, result: MethodChannel.Result) {
        try {
            val account = call.argument<String>("accountId") ?: throw IllegalArgumentException()
            when (call.method) {
                "connection" -> {
                    val saved = connections.read(account)
                    result.success(saved?.let { mapOf(
                        "address" to it.getString("address"),
                        "name" to it.getString("name"),
                        "lastSync" to if (it.has("lastSync")) it.getLong("lastSync") else null
                    ) })
                }
                "remember" -> {
                    val address = call.argument<String>("address") ?: ""
                    val name = call.argument<String>("name") ?: ""
                    val pin = call.argument<String>("pin") ?: ""
                    require(android.bluetooth.BluetoothAdapter.checkBluetoothAddress(address))
                    require(name.isNotBlank() && name.length <= 80 && !name.contains('\u0000'))
                    require(pin.matches(Regex("[0-9]{4}")))
                    connections.save(account, JSONObject(mapOf("address" to address, "name" to name, "pin" to pin)))
                    result.success(null)
                }
                "markSynced" -> {
                    val saved = connections.read(account) ?: throw IllegalStateException()
                    saved.put("lastSync", call.argument<Number>("at")!!.toLong())
                    connections.save(account, saved)
                    result.success(null)
                }
                "forget" -> {
                    if (activeAccount == account) close()
                    connections.forget(account)
                    result.success(null)
                }
            }
        } catch (_: Exception) {
            result.error("connection_storage", "The saved watch connection could not be opened. Disconnect and reconnect your watch.", null)
        }
    }

    private fun requiredPermissions() = if (Build.VERSION.SDK_INT >= 31) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    } else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun hasPermissions() = requiredPermissions().all {
        ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun scan() {
        initSdk()
        val found = linkedMapOf<String, Map<String, Any>>()
        val current = generation
        fun finish() {
            if (generation == current && pending != null) complete(found.values.toList())
        }
        scanning = true
        // The vendor scanner recognises compatible advertisements across model names.
        // A name whitelist would hide other watches using the same supported protocol.
        manager.startScanDevice(8, object : SearchResponse {
            override fun onSearchStarted() {}
            override fun onDeviceFounded(result: SearchResult) {
                handler.post {
                    if (generation == current && pending != null) {
                        val address = result.address
                        val name = result.name?.trimEnd('\u0000')?.trim()?.take(80)
                            ?.takeIf { it.isNotBlank() } ?: "Wearable ${address.takeLast(5)}"
                        found[address] = mapOf("address" to address, "name" to name)
                    }
                }
            }
            override fun onSearchStopped() { handler.post { finish() } }
            override fun onSearchCanceled() { handler.post { finish() } }
        })
        handler.postDelayed({ finish() }, 10000)
    }

    private fun initSdk() {
        if (!initialized) {
            manager.init(activity.applicationContext)
            initialized = true
        }
    }

    private fun read(call: MethodCall) {
        val address = call.argument<String>("address") ?: ""
        val name = call.argument<String>("name") ?: ""
        val pin = call.argument<String>("pin") ?: "0000"
        if (!android.bluetooth.BluetoothAdapter.checkBluetoothAddress(address) || !pin.matches(Regex("[0-9]{4}"))) {
            fail("invalid_watch", "Select a watch and enter its four-digit PIN.")
            return
        }
        initSdk()
        reading = true
        val current = generation
        handler.postDelayed({
            if (current == generation && pending != null) {
                fail("timeout", "The watch did not finish responding. Disconnect it from its companion app, keep it nearby and try Bluetooth again.")
            }
        }, 90000)
        manager.connectDevice(address, name, { code, _, isOta ->
            handler.post {
                if (current == generation && pending != null && (code != Code.REQUEST_SUCCESS || isOta)) {
                    fail("connection", "Could not connect to the watch. Disconnect it from its companion app first, then try Bluetooth again.")
                }
            }
        }, { code ->
            handler.post {
                if (current == generation && pending != null) {
                    if (code == Code.REQUEST_SUCCESS) authenticate(current, pin, name)
                    else fail("connection", "The watch's data service could not be opened.")
                }
            }
        })
    }

    private fun authenticate(current: Int, pin: String, name: String) {
        var authenticated = false
        manager.confirmDevicePwd(writeResponse(current), object : IPwdDataListener {
            override fun onPwdDataChange(data: PwdData) {
                handler.post {
                    if (current != generation || pending == null || authenticated) return@post
                    if (data.getmStatus() == EPwdStatus.CHECK_FAIL) {
                        fail("pin", "The watch PIN was rejected. Check the four-digit PIN and try again.")
                    } else if (data.getmStatus() == EPwdStatus.CHECK_SUCCESS ||
                        data.getmStatus() == EPwdStatus.CHECK_AND_TIME_SUCCESS) {
                        authenticated = true
                        handler.postDelayed({
                            if (current == generation && pending != null) readHistory(current, name)
                        }, 1000)
                    }
                }
            }
            override fun onConnectionConfirmTimeout() {
                handler.post { if (current == generation) fail("confirmation", "Confirm the connection on your watch, then try again.") }
            }
        }, object : IDeviceFuctionDataListener {
            override fun onFunctionSupportDataChange(data: FunctionDeviceSupportData) {
                handler.post {
                    if (current == generation) watchDays = data.wathcDay.coerceIn(1, 30)
                }
            }
            override fun onDeviceFunctionPackage1Report(data: DeviceFunctionPackage1) {}
            override fun onDeviceFunctionPackage2Report(data: DeviceFunctionPackage2) {}
            override fun onDeviceFunctionPackage3Report(data: DeviceFunctionPackage3) {}
            override fun onDeviceFunctionPackage4Report(data: DeviceFunctionPackage4) {}
            override fun onDeviceFunctionPackage5Report(data: DeviceFunctionPackage5) {}
        }, object : ISocialMsgDataListener {
            override fun onSocialMsgSupportDataChange(data: FunctionSocailMsgData) {}
            override fun onSocialMsgSupportDataChange2(data: FunctionSocailMsgData) {}
        }, pin, DateFormat.is24HourFormat(activity))
    }

    private fun readHistory(current: Int, name: String) {
        val info = VpSpGetUtil.getVpSpVariInstance(activity)
        val supportsGlucose = info.isSupportBloodGlucoseDetect || info.isSupportBloodGlucose
        if (!info.isSupportBp && !supportsGlucose) {
            fail("unsupported", "This firmware does not support the readings used by HealthGuide.")
            return
        }
        val rows = linkedMapOf<String, Map<String, Any>>()
        var originRows = 0
        var manualPressureRows = 0
        var manualGlucoseRows = 0
        fun add(at: Long, systolic: Int, diastolic: Int) {
            if (systolic <= 0 || diastolic <= 0) return
            rows["BLOOD_PRESSURE:$at"] = mapOf("at" to at, "metric" to "BLOOD_PRESSURE", "value" to systolic, "secondary" to diastolic)
        }
        fun addGlucose(at: Long, value: Double) {
            if (!supportsGlucose || !value.isFinite() || value <= 0) return
            rows["BLOOD_GLUCOSE:$at"] = mapOf("at" to at, "metric" to "BLOOD_GLUCOSE", "value" to value)
        }
        fun addOrigin(data: OriginData) {
            originRows++
            try {
                val time = data.getmTime()
                val at = LocalDate.parse(data.date).atTime(time.hour, time.minute)
                    .atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                if (info.isSupportBp) add(at, data.highValue, data.lowValue)
                // Veepoo's OriginData3 and manual glucose values are documented in mmol/L.
                if (data is OriginData3) addGlucose(at, data.bloodGlucose.toDouble())
            } catch (_: Exception) {
                // A missing device timestamp cannot be assigned to a trustworthy date.
            }
        }
        fun finish() = complete(mapOf(
            "deviceName" to name,
            "diagnostics" to mapOf(
                "manualHistorySupported" to info.isSupportReadDeviceManual,
                "manualTypes" to if (info.isSupportReadDeviceManual) info.supportReadDeviceManual.map { it.name } else emptyList<String>(),
                "originProtocolVersion" to info.originProtocolVersion,
                "originRows" to originRows,
                "manualPressureRows" to manualPressureRows,
                "manualGlucoseRows" to manualGlucoseRows
            ),
            "readings" to rows.values.sortedBy { it["at"] as Long },
            "supportedTypes" to buildList {
                if (info.isSupportBp) add("BLOOD_PRESSURE")
                if (supportsGlucose) add("BLOOD_GLUCOSE")
            }
        ))
        fun readManual() {
            if (!info.isSupportReadDeviceManual) {
                finish()
                return
            }
            val types = info.supportReadDeviceManual.filter {
                (it == DeviceManualDataType.BLOOD_PRESSURE && info.isSupportBp) ||
                    (it == DeviceManualDataType.BLOOD_GLUCOSE && supportsGlucose)
            }
            if (types.isEmpty()) {
                finish()
                return
            }
            manager.readDeviceManualData(writeResponse(current), 0L, types, types, object : AbsDeviceManualDetectDataListener() {
                override fun onBloodPressureDataChange(data: MutableList<BloodPressureManualData>) {
                    handler.post {
                        if (current == generation && pending != null) {
                            manualPressureRows += data.size
                            for (row in data) add(row.timeStamp.toLong() * 1000, row.systolic, row.diastolic)
                        }
                    }
                }
                override fun onBloodGlucoseDataChange(data: MutableList<BloodGlucoseManualData>) {
                    handler.post {
                        if (current == generation && pending != null) {
                            manualGlucoseRows += data.size
                            for (row in data) addGlucose(row.timeStamp.toLong() * 1000, row.bloodGlucoseValue.toDouble())
                        }
                    }
                }
                override fun onReadComplete() {
                    handler.post { if (current == generation && pending != null) finish() }
                }
                override fun onReadFail() {
                    handler.post { if (current == generation) fail("read_failed", "The watch could not return its manual blood pressure history. Try again.") }
                }
            })
        }
        val progress = object : IOriginProgressListener {
            override fun onReadOriginProgressDetail(day: Int, date: String?, total: Int, position: Int) {}
            override fun onReadOriginProgress(progress: Float) {}
            override fun onReadOriginComplete() {
                handler.post { if (current == generation && pending != null) readManual() }
            }
            override fun onReadTimeout(day: Int) {
                handler.post { if (current == generation) fail("read_failed", "The watch history was incomplete. Try again with the watch nearby.") }
            }
        }
        val listener: IOriginProgressListener = if (info.originProtocolVersion == 3 || info.originProtocolVersion == 5) {
            object : IOriginData3Listener, IOriginProgressListener by progress {
                override fun onOriginFiveMinuteListDataChange(data: MutableList<OriginData3>) {
                    handler.post { if (current == generation && pending != null) data.forEach(::addOrigin) }
                }
                override fun onOriginHalfHourDataChange(data: OriginHalfHourData) {}
                override fun onOriginHRVOriginListDataChange(data: MutableList<HRVOriginData>) {}
                override fun onOriginSpo2OriginListDataChange(data: MutableList<Spo2hOriginData>) {}
            }
        } else {
            object : IOriginDataListener, IOriginProgressListener by progress {
                override fun onOringinFiveMinuteDataChange(data: OriginData) {
                    handler.post { if (current == generation && pending != null) addOrigin(data) }
                }
                override fun onOringinHalfHourDataChange(data: OriginHalfHourData) {}
            }
        }
        manager.readOriginData(writeResponse(current), listener, watchDays)
    }

    private fun writeResponse(current: Int) = object : IBleWriteResponse {
        override fun onResponse(code: Int) {
            if (code != Code.REQUEST_SUCCESS) handler.post {
                if (current == generation) fail("watch_write", "The watch did not accept the history request. Disconnect it from its companion app first, then try Bluetooth again.")
            }
        }
    }

    private fun stopScan() {
        if (!scanning) return
        scanning = false
        try { manager.stopScanDevice() } catch (_: Exception) {}
    }

    private fun release() {
        generation++
        handler.removeCallbacksAndMessages(null)
        permissionAction = null
        activeAccount = null
        stopScan()
        if (reading) {
            reading = false
            try { manager.disconnectWatch(object : IBleWriteResponse {
                override fun onResponse(code: Int) {}
            }) } catch (_: Exception) {}
        }
    }

    private fun complete(value: Any) {
        val result = pending ?: return
        pending = null
        release()
        result.success(value)
    }

    private fun fail(code: String, message: String) {
        val result = pending ?: return
        android.util.Log.w("HealthGuideWatch", "Watch operation failed: $code")
        pending = null
        release()
        result.error(code, message, null)
    }

    fun close() {
        fail("cancelled", "Watch import was cancelled.")
        release()
    }
}
