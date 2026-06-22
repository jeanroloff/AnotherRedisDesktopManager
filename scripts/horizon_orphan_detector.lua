-- Redis Lua script to detect orphaned Horizon Hash keys
-- Usage: redis-cli --eval horizon_orphan_detector.lua horizon:recent_jobs , horizon:job:
-- Args: ARGV[1] = prefix for hash keys (e.g., "horizon:job:")

local zset_key = KEYS[1]
local hash_prefix = ARGV[1]
local cursor = "0"
local orphan_count = 0
local sample_orphans = {}
local max_samples = 20

repeat
    local result = redis.call("SCAN", cursor, "MATCH", hash_prefix .. "*", "COUNT", 1000)
    cursor = result[1]
    local keys = result[2]

    for i = 1, #keys do
        local key = keys[i]
        -- Extract job ID from hash key
        local job_id = string.sub(key, string.len(hash_prefix) + 1)

        -- Check if this job_id exists in the ZSet
        local score = redis.call("ZSCORE", zset_key, job_id)

        if score == false then
            orphan_count = orphan_count + 1
            if #sample_orphans < max_samples then
                table.insert(sample_orphans, key)
            end
        end
    end
until cursor == "0"

return {orphan_count, sample_orphans}
