--!strict
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local digits: { [string]: number } = {}
for i = 1, #alphabet do
    digits[string.sub(alphabet, i, i)] = i - 1
end

return function(encoded: string, size: number): () -> buffer?
    local thread = coroutine.create(function(): buffer
        local compressed = buffer.create(math.floor(#encoded * 3 / 4))
        local accumulator, bits, count = 0, 0, 0
        for i = 1, #encoded do
            local digit = digits[string.sub(encoded, i, i)]
            if digit ~= nil then
                accumulator = accumulator * 64 + digit
                bits += 6
                if bits >= 8 then
                    bits -= 8
                    buffer.writeu8(compressed, count, math.floor(accumulator / 2 ^ bits))
                    count += 1
                    accumulator %= 2 ^ bits
                end
            end
            if i % 16384 == 0 then
                coroutine.yield()
            end
        end
        local result = buffer.create(size)
        local input, output = 0, 0
        local nextYield = 32768
        while input < count do
            local token = buffer.readu8(compressed, input)
            input += 1
            if token < 128 then
                local length = token + 1
                assert(input + length <= count and output + length <= size)
                buffer.copy(result, output, compressed, input, length)
                input += length
                output += length
            else
                assert(input + 2 <= count)
                local distance = buffer.readu16(compressed, input)
                local length = token - 128 + 3
                input += 2
                assert(distance > 0 and distance <= output and output + length <= size)
                for _ = 1, length do
                    buffer.writeu8(result, output, buffer.readu8(result, output - distance))
                    output += 1
                end
            end
            if output >= nextYield then
                nextYield += 32768
                coroutine.yield()
            end
        end
        assert(output == size)
        return result
    end)
    return function(): buffer?
        local ok, result = coroutine.resume(thread)
        assert(ok, tostring(result))
        if coroutine.status(thread) == "dead" then
            return result :: buffer
        end
        return nil
    end
end
