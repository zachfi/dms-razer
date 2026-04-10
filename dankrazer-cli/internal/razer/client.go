package razer

import (
	"fmt"

	"github.com/godbus/dbus/v5"
)

const (
	busName    = "org.razer"
	daemonPath = "/org/razer"

	ifaceDevices = "razer.devices"
	ifaceDaemon  = "razer.daemon"
)

// Client communicates with the OpenRazer daemon over D-Bus.
type Client struct {
	conn *dbus.Conn
}

// NewClient connects to the session bus and returns a Client.
func NewClient() (*Client, error) {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return nil, fmt.Errorf("connect session bus: %w", err)
	}
	return &Client{conn: conn}, nil
}

// Close releases the D-Bus connection.
func (c *Client) Close() error {
	return c.conn.Close()
}

// DaemonVersion returns the openrazer-daemon version string.
func (c *Client) DaemonVersion() (string, error) {
	obj := c.conn.Object(busName, daemonPath)
	call := obj.Call(ifaceDaemon+".version", 0)
	if call.Err != nil {
		return "", call.Err
	}
	var v string
	if err := call.Store(&v); err != nil {
		return "", err
	}
	return v, nil
}

// DeviceSerials returns the serial numbers of all connected Razer devices.
func (c *Client) DeviceSerials() ([]string, error) {
	obj := c.conn.Object(busName, daemonPath)
	call := obj.Call(ifaceDevices+".getDevices", 0)
	if call.Err != nil {
		return nil, call.Err
	}
	var serials []string
	if err := call.Store(&serials); err != nil {
		return nil, err
	}
	return serials, nil
}

// Device returns a handle to a specific device by serial number.
func (c *Client) Device(serial string) *Device {
	path := dbus.ObjectPath(fmt.Sprintf("/org/razer/device/%s", serial))
	return &Device{
		obj:    c.conn.Object(busName, path),
		Serial: serial,
	}
}

// Devices returns handles for all connected devices.
func (c *Client) Devices() ([]*Device, error) {
	serials, err := c.DeviceSerials()
	if err != nil {
		return nil, err
	}
	devices := make([]*Device, len(serials))
	for i, s := range serials {
		devices[i] = c.Device(s)
	}
	return devices, nil
}
