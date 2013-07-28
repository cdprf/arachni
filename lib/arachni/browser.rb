=begin
    Copyright 2010-2013 Tasos Laskos <tasos.laskos@gmail.com>

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
=end

require 'watir-webdriver'

module Arachni

# Real browser driver providing DOM/JS/AJAX support.
#
# @author Tasos "Zapotek" Laskos <tasos.laskos@gmail.com>
class Browser

    # @return   [Hash]   Preloaded resources, by URL.
    attr_reader :preloads

    # @return   [Watir::Browser]   Watir driver interface.
    attr_reader :watir

    def initialize
        proxy.start_async

        @watir = ::Watir::Browser.new(
            Selenium::WebDriver.for( :phantomjs,
                desired_capabilities: Selenium::WebDriver::Remote::Capabilities.
                                          phantomjs( phantomjs_options ),
                args: "--proxy=http://#{proxy.address}/ --ignore-ssl-errors=true"
            )
        )

        @pages    = {}
        @cache    = {}
        @preloads = {}

        @current_response = nil
    end

    # @return   [String]    Current URL.
    def url
        @url || @current_response.url
    end

    # @return   [Page]  Converts the current browser window to a {Page page}.
    def to_page
        return if !@current_response
        @current_response.body = source

        page = @current_response.to_page
        page.cookies |= cookies
        page
    end

    # @param    [String, HTTP::Response, Page]  resource
    #   Loads the given resource in the browser. If it is a string it will be
    #   treated like a URL.
    def load( resource )
        case resource
            when String
                @url = resource

                load_cookies
                watir.goto resource

            when HTTP::Response, Page
                url = preload( resource ).url

                load_cookies
                watir.goto url
        end
        nil
    end

    # @note The preloaded resource will be removed once used, for a persistent
    #   cache use {#cache}.
    #
    # @param    [HTTP::Response, Page]  resource
    #   Preloads a resource to be instantly available by URL via {#load}.
    def preload( resource )
        response =  case resource
                        when HTTP::Response
                            resource

                        when Page
                            resource.response
                    end

        @preloads[response.url] = response
    end

    # @param    [HTTP::Response, Page]  resource
    #   Cache a resource in order to be instantly available by URL via {#load}.
    def cache( resource = nil )
        return @cache if !resource

        response =  case resource
                        when HTTP::Response
                            resource

                        when Page
                            resource.response
                    end

        @cache[response.url] = response
    end

    # Starts capturing requests and parsing them into elements of pages,
    # accessible via {#flush_pages}.
    #
    # @see #stop_capture
    # @see #capture?
    # @see #flush_pages
    def start_capture
        @capture = true
    end

    # Stops the page capture.
    #
    # @see #start_capture
    # @see #capture?
    # @see #flush_pages
    def stop_capture
        @capture = false
    end

    # @return   [Bool]
    #   `true` if the page capture is enabled, `false` otherwise.
    #
    # @see #start_capture
    # @see #stop_capture
    def capture?
        !!@capture
    end

    # @return   [Array<Page>]   Flushes the buffer of recorded pages.
    #
    # @see #start_capture
    # @see #stop_capture
    # @see #capture?
    def flush_pages
        @pages.values
    ensure
        @pages.clear
    end

    # @return   [Array<Cookie>]   Browser cookies.
    def cookies
        watir.cookies.to_a.map { |c| Cookie.new c.merge( url: url ) }
    end

    # @return   [String]   HTML code of the evaluated (DOM/JS/AJAX) page.
    def source
        watir.html
    end

    # @return   [Selenium::WebDriver::Driver]   Selenium driver interface.
    def selenium
        watir.driver
    end

    private

    def load_cookies
        HTTP::Client.cookies.each do |cookie|
            c = cookie.to_h
            next if !c[:name]

            watir.cookies.add c.delete( :name ), c.delete( :value ), c
        end
    end

    def phantomjs_options
        {
            'phantomjs.page.settings.userAgent' => Options.user_agent
        }
    end

    def proxy
        @proxy ||= HTTP::ProxyServer.new(
            request_handler: method( :request_handler )
        )
    end

    def request_handler( request, response )
        if (preloaded = preloads.delete( request.url ))
            copy_response_data( preloaded, response )
            @current_response = preloaded
            return
        end

        if (cached = @cache[request.url])
            copy_response_data( cached, response )
            @current_response = cached
            return
        end

        return true if !capture?

        if !@pages.include? url
            page = Page.from_data( url: url )
            page.response.request = request
            @pages[url] = page
        end

        page = @pages[url]

        case request.method
            when :get
                page.links << Link.new( url: url, action: request.url )

            when :post
                page.forms << Form.new(
                    url:    url,
                    action: request.url,
                    method: request.method,
                    inputs: Utilities.form_parse_request_body( request.body )
                )

            else
                return true
        end

        true
    end

    def copy_response_data( source, destination )
        [:code, :url, :body, :headers, :ip_address, :return_code,
         :return_message, :headers_string, :total_time, :time,
         :version].each do |m|
            destination.send "#{m}=", source.send( m )
        end
        nil
    end

end
end
