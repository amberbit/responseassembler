#--
# Copyright (c) 2009 Hubert Lepicki <hubert.lepicki@amberbit.com>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'rack'
require 'pp'

# This class is piece of Rack middleware that filters responses from your
# app and finds {{{ get /some/relative/url }}} or {{{ xhrget /some/ajax/url }}}
# and substitutes them with appropriate responses returned by your app.
# This can be useful if you want to assemble single page with responses returned
# by many controllers for example.
# xhrget performs standard GET request as well, and tries to mimick 
# XMLHTTPRequest so you can use "if request.xhr?; render :layout => false; end"
# the same way you'd use it with JavaScript, to keep your controllers lean and
# clean.
class Rack::ResponseAssembler
  
  # In Rails you could use:
  # config.middleware.use "Rack::ResponseAssembler", "Yo! Can't load parts!", ["text/html"]
  # to change error message and content types array that filter gets run on.
  def initialize(app, error_message = "<p>Part loading failed...</p>", content_types = ["text/html", "text/xhtml", "text/css", "text/csv", "text/plain"])
    @app = app
    @content_types = content_types
    @error_message = error_message
  end

  def call(env)
    @original_env = env.clone
    
    # First, let's get response from app/rack-cache for user request and return it if not text
    status, headers, response = @app.call(env)
    return [status, headers, response] unless is_allowed_content_type(headers["Content-Type"].to_s)

    response = join_response(response) # merge it into one String

    # Now, let's look for {{{ get /url }}} tags and assemble full page to send out
    response = assemble_from_parts(response)
    headers["Content-Length"] = response.length.to_s
    [status, headers, response]
  end

  def assemble_from_parts(resp_body)
    resp_body.gsub(/(\{\{\{)( *)(get|xhrget)( +)(.*)( *)(\}\}\})/) {
      if $3 == "get"
        assemble_from_parts(get($5))
      else
        assemble_from_parts(get($5, true))
      end
    }
  end  

  def get(relative_url, ajax=false)
    path_string, query_string = relative_url.split("?")
    
    env = @original_env.merge({
      "REQUEST_PATH" => path_string,
      "PATH_INFO" => path_string,
      "REQUEST_URI" => path_string,
      "REQUEST_METHOD" => "GET",
      "QUERY_STRING" => (query_string || '')
    })
    
    env = env.merge({"HTTP_X_REQUESTED_WITH"=>"XMLHttpRequest"}) if ajax 
    
    status, headers, response = @app.call(env)
    return join_response(response) if status == 200
    @error_message 
  end

  def is_allowed_content_type(content_type)
    @content_types.each { |type| return true if content_type =~ Regexp.new(type) }
    false
  end

  def join_response(resp)
    joined = ""
    resp.each { |element| joined += element }
    joined
  end
end

