require 'sinatra'
require 'json'
require 'net/http'
require 'uri'

$background_queue = Queue.new

Thread.new do
   require 'pp'
   while true do
      puts "Wait For Work..."
      request_obj = $background_queue.pop
      begin
         handle_request request_obj
      rescue
         puts "Request Failed: " + request_obj.inspect
      end
   end
end

BASE_PATH='/deploybot/'
HEALTH_CHECK_STR='RUNNNING'

get BASE_PATH do
   return HEALTH_CHECK_STR
end

post BASE_PATH do
   request.body.rewind
   request_body = request.body.read
   begin
      request_obj = JSON.parse request_body
   rescue JSON::ParserError
      halt 400, {'Content-Type' => 'text/plain'}, 'bad request'
   end
   unless valid_request? request_obj
      halt 400, {'Content-Type' => 'text/plain'}, 'bad request'
   end
   unless request_obj["new_thread"] == true
      $background_queue.push request_obj
      return "OK"
   end
   return handle_request request_obj
end

def valid_request? request_obj
   return request_obj.has_key? "message"
end

def handle_request request_obj
   DeploybotSlackBackend.post_message request_obj['message'],
         request_obj['thread_ts']
end

class DeploybotSlackBackend
   SLACK_API_URI = "https://slack.com/api/chat.postMessage"
   class << self
      def post_message message, thread_ts = nil
         uri = URI.parse(SLACK_API_URI)
         request = build_request uri
         request.body = build_request_body message, thread_ts
         response_obj = fetch_response_from_slack uri, request
         p response_obj

         return build_response response_obj['ok'], response_obj['ts']
      end

      private
      def build_request uri
         headers = {
            'Content-Type' =>'application/json',
            'Authorization' => 'Bearer ' + get_api_token,
         }
         return Net::HTTP::Post.new(uri, headers)
      end

      def build_request_body message, thread_ts
         request_obj = {
            "channel": get_channel_id,
            "as_user":true,
            "text": message,
         }
         request_obj["thread_ts"] = thread_ts unless thread_ts.nil?
         p request_obj
         return JSON.generate(request_obj)
      end

      def fetch_response_from_slack uri, request
         req_options = { use_ssl: uri.scheme == "https" }
         response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
              http.request(request)
         end
         return JSON.parse(response.body)
      end

      def get_api_token
         return ENV['DEPLOYBOT_TOKEN']
      end

      def get_channel_id 
         return ENV['DEPLOYBOT_CHANNEL']
      end

      def build_response return_code = 200, thread_ts = nil
         response_obj = {
            "slack_status" => return_code,
            "thread_ts" => thread_ts,
         }
         return JSON.generate(response_obj)
      end
   end
end
