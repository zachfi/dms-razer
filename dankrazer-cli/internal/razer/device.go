package razer

import (
	"fmt"

	"github.com/godbus/dbus/v5"
)

const (
	ifaceMisc       = "razer.device.misc"
	ifaceChroma     = "razer.device.lighting.chroma"
	ifaceBrightness = "razer.device.lighting.brightness"
	ifaceDPI        = "razer.device.dpi"
	ifacePower      = "razer.device.power"
)

// DeviceInfo holds identifying information about a Razer device.
type DeviceInfo struct {
	Serial       string  `json:"serial"`
	Name         string  `json:"name"`
	Type         string  `json:"type"`
	Firmware     string  `json:"firmware"`
	Driver       string  `json:"driver_version"`
	HasMatrix    bool    `json:"has_matrix"`
	MatrixRows   int     `json:"matrix_rows,omitempty"`
	MatrixCols   int     `json:"matrix_cols,omitempty"`
	Brightness   float64 `json:"brightness"`
	DPI          []int   `json:"dpi,omitempty"`
	Battery      float64 `json:"battery,omitempty"`
	IsCharging   bool    `json:"is_charging,omitempty"`
	PollRate     int     `json:"poll_rate,omitempty"`
}

// Device wraps a D-Bus object for a single Razer device.
type Device struct {
	obj    dbus.BusObject
	Serial string
}

func (d *Device) call(iface, method string, args ...any) *dbus.Call {
	return d.obj.Call(iface+"."+method, 0, args...)
}

func (d *Device) getString(iface, method string) (string, error) {
	call := d.call(iface, method)
	if call.Err != nil {
		return "", call.Err
	}
	var v string
	return v, call.Store(&v)
}

func (d *Device) getBool(iface, method string) (bool, error) {
	call := d.call(iface, method)
	if call.Err != nil {
		return false, call.Err
	}
	var v bool
	return v, call.Store(&v)
}

func (d *Device) getFloat(iface, method string) (float64, error) {
	call := d.call(iface, method)
	if call.Err != nil {
		return 0, call.Err
	}
	var v float64
	return v, call.Store(&v)
}

func (d *Device) getInt(iface, method string) (int, error) {
	call := d.call(iface, method)
	if call.Err != nil {
		return 0, call.Err
	}
	var v int
	return v, call.Store(&v)
}

// Name returns the device's product name.
func (d *Device) Name() (string, error) {
	return d.getString(ifaceMisc, "getDeviceName")
}

// Type returns the device type (keyboard, mouse, mousemat, etc.).
func (d *Device) Type() (string, error) {
	return d.getString(ifaceMisc, "getDeviceType")
}

// Firmware returns the firmware version.
func (d *Device) Firmware() (string, error) {
	return d.getString(ifaceMisc, "getFirmware")
}

// DriverVersion returns the driver version.
func (d *Device) DriverVersion() (string, error) {
	return d.getString(ifaceMisc, "getDriverVersion")
}

// HasMatrix returns whether the device supports a key matrix.
func (d *Device) HasMatrix() (bool, error) {
	return d.getBool(ifaceMisc, "hasMatrix")
}

// MatrixDimensions returns [rows, cols] for the device matrix.
func (d *Device) MatrixDimensions() (int, int, error) {
	call := d.call(ifaceMisc, "getMatrixDimensions")
	if call.Err != nil {
		return 0, 0, call.Err
	}
	var dims []int
	if err := call.Store(&dims); err != nil {
		return 0, 0, err
	}
	if len(dims) < 2 {
		return 0, 0, fmt.Errorf("unexpected matrix dimensions: %v", dims)
	}
	return dims[0], dims[1], nil
}

// Brightness returns the device brightness (0-100).
func (d *Device) Brightness() (float64, error) {
	return d.getFloat(ifaceBrightness, "getBrightness")
}

// SetBrightness sets the device brightness (0-100).
func (d *Device) SetBrightness(level float64) error {
	return d.call(ifaceBrightness, "setBrightness", level).Err
}

// DPI returns the current [x, y] DPI values.
func (d *Device) DPI() ([]int, error) {
	call := d.call(ifaceDPI, "getDPI")
	if call.Err != nil {
		return nil, call.Err
	}
	var dpi []int
	return dpi, call.Store(&dpi)
}

// SetDPI sets the DPI for x and y axes.
func (d *Device) SetDPI(x, y uint16) error {
	return d.call(ifaceDPI, "setDPI", x, y).Err
}

// PollRate returns the current polling rate.
func (d *Device) PollRate() (int, error) {
	return d.getInt(ifaceMisc, "getPollRate")
}

// Battery returns the battery percentage (0-100). Only for wireless devices.
func (d *Device) Battery() (float64, error) {
	return d.getFloat(ifacePower, "getBattery")
}

// IsCharging returns whether the device is charging. Only for wireless devices.
func (d *Device) IsCharging() (bool, error) {
	return d.getBool(ifacePower, "isCharging")
}

// Info gathers all available device information.
func (d *Device) Info() DeviceInfo {
	info := DeviceInfo{Serial: d.Serial}

	info.Name, _ = d.Name()
	info.Type, _ = d.Type()
	info.Firmware, _ = d.Firmware()
	info.Driver, _ = d.DriverVersion()
	info.HasMatrix, _ = d.HasMatrix()
	info.Brightness, _ = d.Brightness()
	info.DPI, _ = d.DPI()
	info.PollRate, _ = d.PollRate()

	if info.HasMatrix {
		info.MatrixRows, info.MatrixCols, _ = d.MatrixDimensions()
	}

	// Battery info — silently ignore errors for wired devices
	info.Battery, _ = d.Battery()
	info.IsCharging, _ = d.IsCharging()

	return info
}

// --- Lighting Effects ---

// SetStatic sets a static color effect.
func (d *Device) SetStatic(r, g, b byte) error {
	return d.call(ifaceChroma, "setStatic", r, g, b).Err
}

// SetBreathSingle sets a single-color breathing effect.
func (d *Device) SetBreathSingle(r, g, b byte) error {
	return d.call(ifaceChroma, "setBreathSingle", r, g, b).Err
}

// SetBreathDual sets a dual-color breathing effect.
func (d *Device) SetBreathDual(r1, g1, b1, r2, g2, b2 byte) error {
	return d.call(ifaceChroma, "setBreathDual", r1, g1, b1, r2, g2, b2).Err
}

// SetBreathRandom sets a random-color breathing effect.
func (d *Device) SetBreathRandom() error {
	return d.call(ifaceChroma, "setBreathRandom").Err
}

// SetWave sets a wave effect. Direction: 1=left-to-right, 2=right-to-left.
func (d *Device) SetWave(direction int) error {
	return d.call(ifaceChroma, "setWave", direction).Err
}

// SetSpectrum sets the spectrum cycling (rainbow) effect.
func (d *Device) SetSpectrum() error {
	return d.call(ifaceChroma, "setSpectrum").Err
}

// SetReactive sets the reactive effect. Speed: 1-4 (slow to fast).
func (d *Device) SetReactive(r, g, b, speed byte) error {
	return d.call(ifaceChroma, "setReactive", r, g, b, speed).Err
}

// SetStarlightRandom sets random starlight effect. Speed: 1-3.
func (d *Device) SetStarlightRandom(speed byte) error {
	return d.call(ifaceChroma, "setStarlightRandom", speed).Err
}

// SetStarlightSingle sets single-color starlight. Speed: 1-3.
func (d *Device) SetStarlightSingle(r, g, b, speed byte) error {
	return d.call(ifaceChroma, "setStarlightSingle", r, g, b, speed).Err
}

// SetNone turns off lighting.
func (d *Device) SetNone() error {
	return d.call(ifaceChroma, "setNone").Err
}
