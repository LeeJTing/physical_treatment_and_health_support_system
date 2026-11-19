package com.physical_treatment_and_health_support_system.tarumt.physical_treatment_and_health_support_system

import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.format.DateFormat
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.inuker.bluetooth.library.Code
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

/** One bounded scan or read at a time. Device records are returned for review before saving. */
class VeepooWatchBridge(private val activity: FlutterFragmentActivity) : MethodChannel.MethodCallHandler {
    private val handler = Handler(Looper.getMainLooper())
    private val manager get() = VPOperateManager.getInstance()
    private var pending: MethodChannel.Result? = null
    private var permissionAction: (() -> Unit)? = null
    private var generation = 0
    private var scanCallback: ScanCallback? = null
    private var initialized = false
    private var reading = false
    private var watchDays = 3
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
        if (call.method != "scan" && call.method != "readBloodPressure") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("busy", "A watch operation is already running.", null)
            return
        }
        pending = result
        generation++
        val action = {
            try {
                val bluetooth = activity.getSystemService(BluetoothManager::class.java).adapter
                if (bluetooth?.isEnabled != true) {
                    fail("bluetooth_off", "Turn on Bluetooth, then try again.")
                } else if (call.method == "scan") {
                    scan()
                } else {
                    read(call)
                }
            } catch (_: SecurityException) {
                fail("permission", "Allow Nearby devices access in your phone's app settings.")
            } catch (_: Exception) {
                fail("watch_error", "The watch could not be read. Close H Band and try again.")
            } catch (_: LinkageError) {
                fail("sdk_error", "The watch integration could not start on this device.")
            }
        }
        if (hasPermissions()) action() else {
            permissionAction = action
            permissions.launch(requiredPermissions())
        }
    }

    private fun requiredPermissions() = if (Build.VERSION.SDK_INT >= 31) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    } else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun hasPermissions() = requiredPermissions().all {
        ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun scan() {
        val scanner = activity.getSystemService(BluetoothManager::class.java).adapter.bluetoothLeScanner
        val found = linkedMapOf<String, Map<String, Any>>()
        val current = generation
        val callback = object : ScanCallback() {
            override fun onScanResult(type: Int, result: ScanResult) {
                val name = result.scanRecord?.deviceName?.trimEnd('\u0000')?.trim() ?: return
                if (!name.contains("K202", true) && !name.contains("KS02", true)) return
                handler.post {
                    if (generation == current && pending != null) {
                        found[result.device.address] = mapOf("address" to result.device.address, "name" to name)
                    }
                }
            }
            override fun onScanFailed(errorCode: Int) {
                handler.post { if (generation == current) fail("scan_failed", "Bluetooth scan failed. Try again.") }
            }
        }
        scanCallback = callback
        scanner.startScan(callback)
        handler.postDelayed({
            if (generation == current && pending != null) {
                stopScan()
                complete(found.values.toList())
            }
        }, 8000)
    }

    private fun read(call: MethodCall) {
        val address = call.argument<String>("address") ?: ""
        val name = call.argument<String>("name") ?: ""
        val pin = call.argument<String>("pin") ?: "0000"
        if (!android.bluetooth.BluetoothAdapter.checkBluetoothAddress(address) || !pin.matches(Regex("[0-9]{4}"))) {
            fail("invalid_watch", "Select a watch and enter its four-digit PIN.")
            return
        }
        if (!initialized) {
            manager.init(activity.applicationContext)
            initialized = true
        }
        reading = true
        val current = generation
        handler.postDelayed({
            if (current == generation && pending != null) {
                fail("timeout", "The watch did not finish responding. Close H Band, keep the watch nearby and try again.")
            }
        }, 90000)
        manager.connectDevice(address, name, { code, _, isOta ->
            handler.post {
                if (current == generation && pending != null && (code != Code.REQUEST_SUCCESS || isOta)) {
                    fail("connection", "Could not connect to the watch. Close H Band and try again.")
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
        if (!info.isSupportBp) {
            fail("unsupported", "This watch firmware does not report support for blood pressure records.")
            return
        }
        val rows = linkedMapOf<Long, Map<String, Any>>()
        fun add(at: Long, systolic: Int, diastolic: Int) {
            if (systolic <= 0 || diastolic <= 0) return
            rows[at] = mapOf("at" to at, "systolic" to systolic, "diastolic" to diastolic)
        }
        fun addOrigin(data: OriginData) {
            try {
                val time = data.getmTime()
                val at = LocalDate.parse(data.date).atTime(time.hour, time.minute)
                    .atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                add(at, data.highValue, data.lowValue)
            } catch (_: Exception) {
                // A missing device timestamp cannot be assigned to a trustworthy date.
            }
        }
        fun finish() = complete(mapOf(
            "deviceName" to name,
            "readings" to rows.values.sortedBy { it["at"] as Long },
            "storedDays" to watchDays
        ))
        fun readManual() {
            val types = listOf(DeviceManualDataType.BLOOD_PRESSURE)
            if (!info.isSupportReadDeviceManual || !info.supportReadDeviceManual.contains(DeviceManualDataType.BLOOD_PRESSURE)) {
                finish()
                return
            }
            manager.readDeviceManualData(writeResponse(current), 0L, types, types, object : AbsDeviceManualDetectDataListener() {
                override fun onBloodPressureDataChange(data: MutableList<BloodPressureManualData>) {
                    handler.post {
                        if (current == generation && pending != null) {
                            for (row in data) add(row.timeStamp.toLong() * 1000, row.systolic, row.diastolic)
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
                if (current == generation) fail("watch_write", "The watch did not accept the history request. Close H Band and try again.")
            }
        }
    }

    private fun stopScan() {
        try {
            scanCallback?.let { activity.getSystemService(BluetoothManager::class.java).adapter.bluetoothLeScanner?.stopScan(it) }
        } catch (_: Exception) {}
        scanCallback = null
    }

    private fun release() {
        generation++
        handler.removeCallbacksAndMessages(null)
        permissionAction = null
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
        pending = null
        release()
        result.error(code, message, null)
    }

    fun close() {
        fail("cancelled", "Watch import was cancelled.")
        release()
    }
}
