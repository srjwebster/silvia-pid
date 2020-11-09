#!/usr/bin/env python
import mcp9600

a = mcp9600.TemperatureAdapter()
m = mcp9600.MCP9600(0x60)
t = m.get_hot_junction_temperature()
t = t
print(t)
exit