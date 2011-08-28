require 'net/http'
require 'uri'

# Class for interacting with the TxtImpact sms sending and receiving service.
# Example usage:
#   connection = TxtImpact.new(:username => 'your_username',
#     :password => 'your password',
#     :profile_id => 42,
#     :short_code => 1111,
#     :vasid => 12345)
#   connection.send_sms()
class Wire2Air


  class FailedAuthenticationError < StandardError; end
  class NotEnoughCreditsError < StandardError; end
  class KeywordIsTakenError < StandardError; end
  class AccountUpdateError  < StandardError; end
  class CreditCardDeclinedError < StandardError; end


  class JobId
    def initialize(mobile_number, sms_id)
      @mobile_number, @sms_id = mobile_number, sms_id
    end
    attr_reader :mobile_number, :sms_id
    def self.from_s(str)
      matches = str.match /^JOBID: (\d+):(\d+)/
      JobId.new(matches[1], matches[2])
    end
  end


  # Initializes a TxtImpact object with the common profile info needed
  # for making connections.
  # @param [Hash] opts The profile connection options
  # @option opts [String] :username The user name to connect as
  # @option opts [String] :password The password (in plain text) for connecting
  # @option opts [Integer] :profile_id The id of the profile
  # @options opts [Integer] :short_code The short code for the account
  # @options opts [Integer] :vasid The vasid of the account
  def initialize(opts)
    valid_keys =[:username, :password, :profile_id, :short_code, :vasid]
    if opts.keys.sort != valid_keys.sort
      puts opts.keys
      raise ArgumentError.new "The options must only have the keys #{valid_keys}"
    end

    opts.each do |key, value|
      instance_variable_set("@#{key}", value)
    end

  end

  attr_reader :username, :password, :vasid, :profile_id, :short_code

  alias :userid :username

  public
  # sends an sms
  # @param [String, Array<String>] to_number DESTINATION MOBILE NUMBER. [(country
  #   code) + mobile number] e.g 17321234567 (for
  #   US), 919810601000 (for India)
  # @param [String] text The message text
  # @param [Hash] opts Extra optional settings
  # @option  opts [String] :batch_reference A reference string used when sending many sms
  # @option opts [String] :network_id Th id of the destination network. This is the same as
  # what is passed from incoming sms message for the HTTP API.
  # @return [JobId, Integer] If a single sms is being sent, a JobId is returned. Otherwise
  # an Integer for the BatchID is returned.
  # @raise NotEnoughError Not enough credits to send the sms
  # @raise FailedAuthenticationError some authentication details are wrong
  def send_sms(to_number, text, opts = {})
    params = common_options
    params['VERSION'] = '2.0'
    params['FROM'] = short_code
    params['TEXT'] = text
    params['NETWORKID'] = opts[:network_id] if opts.has_key? :network_id
    batch_send = !(to_number.is_a? String)

    if !batch_send
      params['TO'] = to_number
    else
      params['TO'] = to_number.join(',')
      params['BATCHNAME'] = opts[:batch_reference]

    end

    p params

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
  def subscribe_credits(keyword_credits = 1)
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
  def credit_count
    url = URI.parse('http://smsapi.wire2air.com/smsadmin/checksmscredits.aspx')
    res = Net::HTTP.post_form(url, {
        'USERID' => userid,
        'PASSWORD' => password,
        'VASID' => vasid
    }).body
    raise FailedAuthenticationError if res =~ /ERR: 301/
    res.to_i
  end

  # Checks whether the keyword can be registered.
  # @return Boolean true if the keyword is available
  def is_keyword_available?(keyword)
    url = URI.parse('http://mzone.wire2air.com/shortcodemanager/api/checkkeywordapi.aspx')
    response = Net::HTTP.post_form(url, {
        'USERID' => userid,
        'PASSWORD' => password,
        'VASID' => vasid,
        'SHORTCODEID' => short_code,
        'KEYWORD' => keyword
    })

    response.body.include? "Err:0:"


  end


  # registers a keyword
  # @param opts Options for creating the keyword
  # @option opts [String] :service_name Service name for the keyword
  # @option opts [String] :keyword
  # @option opts [String] :processor_url The url of the webserice
  # @option opts [String] :help_msg Response for help message
  # @option opts [String] :stop_msg Responce for opt-out message
  # @return [Integer] The service id
  # @raise ArgumentError If arguments are missing/invalid
  # @raise KeywordIsTakenError
  def register_keyword(opts)
    url = URI.parse('http://mzone.wire2air.com/shortcodemanager/api/RegisterKeywordAPI.aspx')
    params = common_options
    params['SHORTCODEID'] = short_code
    params['SERVICENAME'] = opts[:service_name]
    params['KEYWORD'] = opts[:keyword]
    params['PROCESSORURL'] = opts[:processor_url]
    params['HELPMSG'] = opts[:help_msg]
    params['STOPMSG'] = opts[:stop_msg]
    params['ACTION'] = 'ADD'

    res = Net::HTTP.post_form(url, params).body

    case res
      when /Err:70[012346789]/, /Err:71[0134]/
        raise ArgumentError.new res
      when /Err:705/
        raise KeywordIsTakenError
      when /Err:712/
        raise "Sticky session is not allowed"
    end

    res.match(/SERVICEID:(\d+)/)[1].to_i

  end

  # deletes a service created with register_keyword.
  # @param [Integer] service_id The id of the service to delete
  # @param [String] keyword the keyword for the service
  def delete_service(service_id, keyword)
    url = URI.parse('http://mzone.wire2air.com/shortcodemanager/api/RegisterKeywordAPI.aspx')
    params = common_options
    params.delete 'PROFILEID'
    params['SHORTCODEID'] = short_code
    params['SERVICEID'] = service_id.to_s
    params['KEYWORD'] = keyword
    params['ACTION'] = 'DELETE'
    p params
    res = Net::HTTP.post_form(url, params)
    raise StandardError.new res.body unless res.body.start_with? "SERVICEID"
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


