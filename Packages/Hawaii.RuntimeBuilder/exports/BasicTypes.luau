local BasicTypes = {}
type OffsetPointer = {offset: number}

-- Reads a ULEB128, returns the read number and bytes read

function BasicTypes.ULEB128(b: buffer, offsetPtr: OffsetPointer): number
	local result = 0
	local shift = 0
	local bytesRead = 0
	local offset = offsetPtr.offset

	while true do
		-- Read the current byte
		local byte = buffer.readu8(b, offset)
		offset += 1
		bytesRead += 1

		-- Extract the value (7 bits) and accumulate into result
		result = result + bit32.band(byte, 0x7F) * 2^shift
		shift += 7

		-- Check the MSB; if 0, we're done
		if bit32.band(byte, 0x80) == 0 then
			break
		end
	end

	offsetPtr.offset = offset
	return result
end

function BasicTypes.ReadString(b: buffer, offsetPtr: OffsetPointer): string
	local sizeof = BasicTypes.ULEB128(b, offsetPtr)
	local offset = offsetPtr.offset
	offsetPtr.offset += sizeof

	return buffer.readstring(b, offset, sizeof)
end

function BasicTypes.Hash256(b: buffer, offsetPtr: OffsetPointer): string
	--- read 4 subsections
	local offset = offsetPtr.offset
	offsetPtr.offset += 16
	local H1, H2, H3, H4 = 
		buffer.readu32(b, offset),
		buffer.readu32(b, offset + 4),
		buffer.readu32(b, offset + 8),
		buffer.readu32(b, offset + 12)

	return string.format("%x%x%x%x", H1, H2, H3, H4)
end

return BasicTypes