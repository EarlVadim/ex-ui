package xray

import (
	"bytes"
	"x-ui/util/json_util"
)

type InboundConfig struct {
	Listen         json_util.RawMessage `json:"listen"` // listen cannot be an empty string
	Port           int                  `json:"port"`
	Extlisten      string               `json:"extlisten"` 
	Extport        int                  `json:"extport"`
	Protocol       string               `json:"protocol"`
	Settings       json_util.RawMessage `json:"settings"`
	StreamSettings json_util.RawMessage `json:"streamSettings"`
	Tag            string               `json:"tag"`
	Cdn            bool                 `json:"cdn"`
	Sniffing       json_util.RawMessage `json:"sniffing"`
}

func (c *InboundConfig) Equals(other *InboundConfig) bool {
	if !bytes.Equal(c.Listen, other.Listen) {
		return false
	}
	if c.Port != other.Port {
		return false
	}
	if c.Extlisten != other.Extlisten {
		return false
	}
	if c.Extport != other.Extport {
		return false
	}
	if c.Protocol != other.Protocol {
		return false
	}
	if !bytes.Equal(c.Settings, other.Settings) {
		return false
	}
	if !bytes.Equal(c.StreamSettings, other.StreamSettings) {
		return false
	}
	if c.Tag != other.Tag {
		return false
	}
	if c.Cdn != other.Cdn {
		return false
	}
	if !bytes.Equal(c.Sniffing, other.Sniffing) {
		return false
	}
	return true
}
