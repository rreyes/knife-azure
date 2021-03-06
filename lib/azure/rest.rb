#
# Author:: Barry Davis (barryd@jetstreamsoftware.com)
# Copyright:: Copyright (c) 2010-2011 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require "net/https"
require "uri"
require "nokogiri"

module AzureAPI

  class Rest
    
    def initialize(params)
      @subscription_id = params[:azure_subscription_id]
      @pem_file = params[:azure_mgmt_cert]
      @host_name = params[:azure_api_host_name]
      @verify_ssl = params[:verify_ssl_cert]
      @content_type = nil
      @x_ms_version = nil
    end

    def set_content_type(content_type)
      @content_type = content_type
    end

    def set_x_ms_version(x_ms_version)
      @x_ms_version = x_ms_version
    end

    def query_azure(service_name,
                    verb = 'get',
                    body = '',
                    params = '',
                    services = true)
                    
                     
                  
      svc_str = services ? '/services' : ''
      request_url =
        "https://#{@host_name}/#{@subscription_id}#{svc_str}/#{service_name}"
      print '.'
      Chef::Log.debug "#{request_url}"
      response = http_query(request_url, verb, body, params)
      if response.code.to_i == 307
        Chef::Log.debug "Redirect to #{response['Location']}"
        response = http_query(response['Location'], verb, body, params)
      end
      @last_request_id = response['x-ms-request-id']
      response
    end

    def http_query(request_url, verb, body, params)
      uri = URI.parse(request_url)
      uri.query = params
      http = http_setup(uri)
      request = request_setup(uri, verb, body)
      response = http.request(request)
      @last_request_id = response['x-ms-request-id']
      response
    end

    def query_for_completion()
      request_url = "https://#{@host_name}/#{@subscription_id}/operations/#{@last_request_id}"
      response = http_query(request_url, 'get', '', '')
      if response.code.to_i == 307
        Chef::Log.debug "Redirect to #{response['Location']}"
        response = http_query(response['Location'], 'get', '', '')
      end
      response
    end

    def http_setup(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      store = OpenSSL::X509::Store.new
      store.set_default_paths
      http.cert_store = store
      if @verify_ssl
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      http.use_ssl = true
      begin
        http.cert = OpenSSL::X509::Certificate.new(@pem_file)
      rescue OpenSSL::X509::CertificateError => err
        raise "Invalid Azure Certificate pem file. Error: #{err}"
      end
        http.key = OpenSSL::PKey::RSA.new(@pem_file)
      http
    end
    def request_setup(uri, verb, body)
      if verb == 'get'
        request = Net::HTTP::Get.new(uri.request_uri)
      elsif verb == 'post'
        request = Net::HTTP::Post.new(uri.request_uri)
      elsif verb == 'delete'
        request = Net::HTTP::Delete.new(uri.request_uri)
      elsif verb == 'put'
        request = Net::HTTP::Put.new(uri.request_uri)
      end

      if @x_ms_version.nil?
        request["x-ms-version"] = "2014-04-01"
      else
        request["x-ms-version"] =  @x_ms_version
      end

      
      # If the content_type has been set then use the content_type instead of the normal flow.
      if @content_type.nil?
        request["content-type"] =  (verb == 'put') ? 'text/plain' : 'application/xml'
      else 
        request["content-type"] =  @content_type
      end
      
      
      request["accept"] = "application/xml"
      request["accept-charset"] = "utf-8"
      request.body = body
      request
    end
    def showResponse(response)
      puts "=== response body ==="
      puts response.body
      puts "=== response.code ==="
      puts response.code
      puts "=== response.inspect ==="
      puts response.inspect
      puts "=== all of the headers ==="
      puts response.each_header { |h, j| puts h.inspect + ' : ' + j.inspect}
    end
  end
end
