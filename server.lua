local json = require 'json' -- Ensure you have a JSON library to encode payloads

-- Configuration
local debug = false -- Set to true to enable debugging messages

-- Webhook URL
local webhookURL = "YOURDISCORDWEBHOOKURL" --

-- Queue for messages to send
local messageQueue = {}
local isProcessingQueue = false
local maxRetries = 5
local retryDelay = 5000 -- 5 seconds
local fetchInterval = 60000 -- 1 minute

-- File to store the last tweet ID
local lastTweetIDFile = "last_tweet_id.txt"

-- Utility function for debugging
local function debugPrint(message)
    if debug then
        print(message)
    end
end

-- Function to send a message to Discord
local function handleSendToDiscord(message, tweet, retryCount)
    retryCount = retryCount or 0

    -- Prepare embed data if there is an image URL
    local embeds = {}
    if tweet.url and tweet.url ~= "" and tweet.url ~= "default" then
        table.insert(embeds, {
            title = tweet.firstName .. " " .. tweet.lastName .. " tweeted:",
            description = message,
            image = {
                url = tweet.url
            }
        })
    else
        -- If no image, use a simple embed with text
        table.insert(embeds, {
            title = tweet.firstName .. " " .. tweet.lastName .. " tweeted:",
            description = message
        })
    end

    -- Prepare payload
    local payload = {
        username = "TweetBot",
        embeds = embeds
    }

    debugPrint("Payload to Discord: " .. json.encode(payload))

    PerformHttpRequest(webhookURL, function(err, text, headers)
        local status = tonumber(err)
        if status == 200 or status == 204 then
            debugPrint("Message sent successfully!")
            processQueue() -- Process the next message in the queue
        elseif status == 429 then
            if retryCount < maxRetries then
                debugPrint("Rate limit hit, retrying in 5 seconds...")
                Citizen.Wait(retryDelay) -- Wait before retrying
                handleSendToDiscord(message, tweet, retryCount + 1)
            else
                debugPrint("Max retries reached. Skipping message.")
                processQueue() -- Process the next message in the queue
            end
        else
            debugPrint("Error sending message to Discord: " .. status .. " " .. text)
            if retryCount < maxRetries then
                Citizen.Wait(retryDelay) -- Wait before retrying on other errors
                handleSendToDiscord(message, tweet, retryCount + 1)
            else
                debugPrint("Max retries reached. Skipping message.")
                processQueue() -- Process the next message in the queue
            end
        end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

-- Function to process the queue
local function processQueue()
    if isProcessingQueue then
        debugPrint("Queue is already being processed.")
        return
    end
    isProcessingQueue = true
    debugPrint("Processing queue...")

    while #messageQueue > 0 do
        local tweetData = table.remove(messageQueue, 1)
        debugPrint("Processing tweet: " .. json.encode(tweetData))
        handleSendToDiscord(tweetData.message, tweetData)
        Citizen.Wait(1000) -- Wait 1 second between each message
    end

    isProcessingQueue = false
    debugPrint("Queue processing complete.")
end

-- Function to read the last tweet ID from file
local function readLastTweetID()
    local file = io.open(lastTweetIDFile, "r")
    if file then
        local id = file:read("*a")
        file:close()
        local tweetID = tonumber(id) or 0
        debugPrint("Read last tweet ID from file: " .. tweetID)
        return tweetID
    end
    debugPrint("File not found or error reading file. Defaulting to ID 0.")
    return 0
end

-- Function to write the last tweet ID to file
local function writeLastTweetID(id)
    local file = io.open(lastTweetIDFile, "w")
    if file then
        file:write(tostring(id))
        file:close()
        debugPrint("Wrote last tweet ID to file: " .. id)
    else
        debugPrint("Error opening file for writing.")
    end
end

-- Function to fetch tweets from the database and enqueue messages
local function fetchTweetsAndEnqueueMessages()
    local lastTweetID = readLastTweetID()
    local query = 'SELECT * FROM phone_tweets WHERE id > ? ORDER BY date ASC'
    debugPrint("Executing query: " .. query)

    exports.oxmysql:query(query, {lastTweetID}, function(result)
        debugPrint("Query result: " .. json.encode(result))

        if not result or type(result) ~= "table" then
            debugPrint("No result or result is not a table")
            return
        end

        -- Enqueue messages with tweet data
        for _, tweet in ipairs(result) do
            local firstName = tweet.firstName or "Unknown"
            local lastName = tweet.lastName or ""
            local message = tweet.message or "No message"
            local tweetID = tweet.id
            local tweetData = {
                firstName = firstName,
                lastName = lastName,
                message = message,
                url = tweet.url
            }
            table.insert(messageQueue, tweetData)

            -- Update the last tweet ID
            if tweetID > lastTweetID then
                writeLastTweetID(tweetID)
            end
        end

        -- Debugging: Confirm fetchTweetsAndEnqueueMessages has finished
        debugPrint("Finished fetching and enqueuing tweets")

        -- Start processing the queue if it's not already being processed
        if not isProcessingQueue then
            processQueue()
        else
            debugPrint("Queue is already being processed.")
        end
    end)
end

-- Periodically fetch tweets and enqueue messages
Citizen.CreateThread(function()
    debugPrint("Starting periodic tweet fetching...")
    while true do
        fetchTweetsAndEnqueueMessages()
        Citizen.Wait(fetchInterval) -- Wait before fetching again
    end
end)
