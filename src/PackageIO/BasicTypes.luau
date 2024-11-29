local BasicTypes = {}
type OffsetPointer = {offset: number}

function BasicTypes.MergeBuffer(b1: buffer, b2: buffer): buffer
	local b1l, b2l = buffer.len(b1), buffer.len(b2)
	local out = buffer.create(b1l + b2l)

	buffer.copy(out, 0, b1, 0)
	buffer.copy(out, b1l, b2, 0)
	return out
end

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

function BasicTypes.ULEB128Size(n: number): number
	if n == 0 then
		return 1
	end

	return math.ceil(math.log(n + 1, 128))
end

function BasicTypes.WriteULEB128(n: number): buffer
	local result = buffer.create(BasicTypes.ULEB128Size(n))
	local offset = 0

	repeat
		local byte = bit32.band(n, 0x7F)
		n = bit32.rshift(n, 7)
		if n ~= 0 then byte = bit32.bor(byte, 0x80) end
		buffer.writeu8(result, offset, byte)
		offset += 1
	until n == 0

	return result
end

function BasicTypes.ReadString(b: buffer, offsetPtr: OffsetPointer): string
	local sizeof = BasicTypes.ULEB128(b, offsetPtr)
	local offset = offsetPtr.offset
	offsetPtr.offset += sizeof
	return buffer.readstring(b, offset, sizeof)
end

-- slow path, for when an existing buffer isn't available
function BasicTypes.WriteString(s: string): buffer
	local sizeof = string.len(s)
	local sizeBuffer = BasicTypes.WriteULEB128(sizeof)

	return BasicTypes.MergeBuffer(sizeBuffer, buffer.fromstring(s))
end

-- fast path, for when a buffer is available
function BasicTypes.InsertULEB128(b: buffer, n: number, offsetPointer: OffsetPointer)
	local offset = offsetPointer.offset
	repeat
		local byte = bit32.band(n, 0x7F)
		n = bit32.rshift(n, 7)
		if n ~= 0 then byte = bit32.bor(byte, 0x80) end
		buffer.writeu8(b, offset, byte)
		offset += 1
	until n == 0

	offsetPointer.offset = offset
end

function BasicTypes.InsertString(b: buffer, s: string, offsetPointer: OffsetPointer)
	local sizeof = string.len(s)

	BasicTypes.InsertULEB128(b, sizeof, offsetPointer)
	buffer.writestring(b, offsetPointer.offset, s)
	offsetPointer.offset += sizeof
end

function BasicTypes.InsertBuffer(b: buffer, i: buffer, offsetPointer: OffsetPointer)
	local sizeof = buffer.len(i)

	BasicTypes.InsertULEB128(b, sizeof, offsetPointer)
	buffer.copy(b, offsetPointer.offset, i)
	offsetPointer.offset += sizeof
end

return BasicTypes