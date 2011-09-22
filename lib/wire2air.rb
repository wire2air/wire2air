require 'net/http'
require 'uri'

# Class for interacting with the Wire2Air sms sending and receiving service.
# Example usage:
#   connection = Wire2Air.new(:username => 'your_username',
#     :password => 'your password',
#     :profile_id => 42,
#     :vasid => 12345) # replace the options with the ones found for your account
#   short_code = 234 # replace with the shortcode from your account you wish to use
#   test_number = "123456789"
#   connection.submit_sm(short_code, test_number, "A message to send")
class Wire2Air


  # Raised when the username or password is wrong
  class FailedAuthenticationError < StandardError; end
  # Raised when there is insufficient credits to perform the action
  class NotEnoughCreditsError < StandardError; end
  # Raised when a keyword being registered is already taken
  class KeywordIsTakenError < StandardError; end
  # Raised when a service error occurred during account update
  class AccountUpdateError  < StandardError; end
  # Raised when the credit card details were declined for purchase of additional credits
  class CreditCardDeclinedError < StandardError; end


  # Stores details on a send sms job
  class JobId
    # creates a job for the given mobile_number and sms_id
    def initialize(mobile_number, sms_id)
      @mobile_number, @sms_id = mobile_number, sms_id
    end
    attr_reader :mobile_number, :sms_id
    # parses a JobId out of the return response from the wire2air http api
    def self.from_s(str)
      matches = str.match /^JOBID: (\d+):(\d+)/
      JobId.new(matches[1], matches[2])
    end
  end


  # Initializes a Wire2Air object with the common profile info needed
  # for making connections.
  # @param [Hash] opts The profile connection options
  # @option opts [String] :username The user name to connect as
  # @option opts [String] :password The password (in plain text) for connecting
  # @option opts [Integer] :profile_id The id of the profile
  # @option opts [Integer] :vasid The vasid of the account
  def initialize(opts)
    valid_keys =[:username, :password, :profile_id, :vasid]
    if opts.keys.sort != valid_keys.sort
      raise ArgumentError.new "The options must only have the keys #{valid_keys}"
    end

    opts.each do |key, value|
      instance_variable_set("@#{key}", value)
    end

  end

  attr_reader :username, :password, :vasid, :profile_id

  alias :userid :username

  public
  # sends an sms
  # @param [String, Array<String>] mobile_number DESTINATION MOBILE NUMBER. [(country
  #   code) + mobile number] e.g 17321234567 (for
  #   US), 919810601000 (for India)
  # @param [String] from The short code number
  # @param [String] text The message text
  # @param [Hash] opts Extra optional settings
  # @option  opts [String] :batch_reference A reference string used when sending many sms
  # @option opts [String] :network_id Th id of the destination network. This is the same as
  # what is passed from incoming sms message for the HTTP API.
  # @return [JobId, Integer] If a single sms is being sent, a JobId is returned. Otherwise
  # an Integer for the BatchID is returned.
  # @raise NotEnoughError Not enough credits to send the sms
  # @raise FailedAuthenticationError some authentication details are wrong
  def submit_sm(from, mobile_number, text, opts = {})
    params = common_options
    params['VERSION'] = '2.0'
    params['FROM'] = from
    params['TEXT'] = text
    params['NETWORKID'] = opts[:network_id] if opts.has_key? :network_id
    batch_send = !(mobile_number.is_a? String)

    if !batch_send
      params['TO'] = mobile_number
    else
      params['TO'] = mobile_number.join(',')
      params['BATCHNAME'] = opts[:batch_reference]

    end

    url = URI.parse('http://smsapi.wire2air.com/smsadmin/submitsm.aspx')
    res = Net::HTTP.post_form(url, params).body
    case res
      when /^ERR: 301/
        raise FailedAuthenticationError
      when /^ERR: 305/
        raise NotEnoughCreditsError
    end
    if (batch_send)
      res.match(/BATCHID: \d+/)[1]
    else
      puts res
      JobId.from_s(res)
    end
  end

  # Adds some credits to the account
  # @param [Integer] keyword_credits The number of credits to add
  # @return [void]
  def subscribe_keywords(keyword_credits = 1)
    url = URI.parse('http://mzone.wire2air.com/mserver/api/subscribekeywords.aspx')
    res = Net::HTTP.post_form(url, {
        'USERID' => userid,
        'PASSWORD' => password,
        'KEYWORDREDITS' => keyword_credits

    })
    case res.body
      when /^Err:70[34]/
        raise ArgumentError.new "Missing username or password"
      when /^Err:705/
        raise KeywordIsTakenError
      when /^Err:300/
        raise FailedAuthenticationError
      when /^Err:715/
        raise AccountUpdateError
      when /^Err:716/
        raise CreditCardDeclinedError
    end

  end

  # returns the number of credits available
  # @return Integer the number of credits available
  def check_sms_credits
    url = URI.parse('http://smsapi.wire2air.com/smsadmin/checksmscredits.aspx')
    res = Net::HTTP.post_form(url, {
        'USERID' => userid,
        'PASSWORD' => password,
        'VASID' => vasid
    }).body
    raise FailedAuthenticationError if res =~ /ERR:301/
    res.to_i
  end

  # Checks whether the keyword can be registered.
  # @param [String] short_code The short code id
  # @param [String] keyword The keyword to search for
  # @return Boolean true if the keyword is available
  def check_keyword(short_code, keyword)
    url = URI.parse('http://mzone.wire2air.com/mserver/servicemanager/api/checkkeywordapi.aspx')
    response = Net::HTTP.post_form(url, {
        'USERID' => userid,
        'PASSWORD' => password,
        'VASID' => vasid,
        'SHORTCODE' => short_code,
        'KEYWORD' => keyword
    })

    case response.body
      when /Err:0/
        return true
      when /Err:705/
        return false
      when /Err:301/
        raise FailedAuthenticationError
      else
        raise StandardError.new response.body
    end

  end


  # Wire2air provides simple HTTP interface for clients to register available keyword
  # for a given short code.
  # @param opts Options for creating the keyword
  # @option opts [String] :service_name Service name for the keyword
  # @option opts [String] :short_code
  # @option opts [String] :keyword
  # @option opts [String] :processor_url The url of the webservice
  # @option opts [String] :help_msg Response for help message
  # @option opts [String] :stop_msg Responce for opt-out message
  # @option opts [String] :action  :add -> Register new service with keyword
  # :delete -> Delete keyword from service
  # Default is :add
  # @return [Integer] The service id
  # @raise ArgumentError If arguments are missing/invalid
  # @raise KeywordIsTakenError
  def register_keyword(opts)
    url = URI.parse('http://mzone.wire2air.com/mserver/servicemanager/api/checkkeywordapi.aspx')
    params = {}
    params['USERID'] = username
    params['PASSWORD'] = password
    params['VASID'] = vasid
    params['SHORTCODE'] = opts[:short_code]
    params['SERVICENAME'] = opts[:service_name]
    params['KEYWORD'] = opts[:keyword]
    params['PROCESSORURL'] = opts[:processor_url]
    params['HELPMSG'] = opts[:help_msg]
    params['STOPMSG'] = opts[:stop_msg]
    params['ACTION'] = (opts[:action] == :delete) ? "DELETE" : "ADD"

    res = Net::HTTP.post_form(url, params).body
    puts res

    case res
      when /Err:70[012346789]/, /Err:71[0134]/
        raise ArgumentError.new res
      when /Err:300/
        raise FailedAuthenticationError
      when /Err:705/
        raise KeywordIsTakenError
      when /Err:712/
        raise "Sticky session is not allowed"
    end

    res.match(/SERVICEID:(\d+)/)[1].to_i

  end

  private
  def common_options
    { 'USERID' => username,
      'PASSWORD' => password,
      'VASID' => vasid,
      'PROFILEID' => profile_id,
    }

  end


end


