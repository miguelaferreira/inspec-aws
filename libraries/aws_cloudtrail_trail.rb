# frozen_string_literal: true

require 'aws_backend'

class AwsCloudTrailTrail < AwsResourceBase
  name 'aws_cloudtrail_trail'
  desc 'Verifies settings for an individual AWS CloudTrail Trail'

  example "
    describe aws_cloudtrail_trail('trail-name') do
      it { should exist }
    end
  "
  attr_reader :cloud_watch_logs_log_group_arn, :cloud_watch_logs_role_arn, :home_region, :exists, :trail_name,
              :kms_key_id, :s3_bucket_name, :trail_arn, :is_multi_region_trail, :log_file_validation_enabled
  alias multi_region_trail? is_multi_region_trail
  alias log_file_validation_enabled? log_file_validation_enabled
  alias has_log_file_validation_enabled? log_file_validation_enabled
  alias exists? exists

  def initialize(opts = {})
    # Call the parent class constructor
    opts = { trail_name: opts } if opts.is_a?(String) # this preserves the original scalar interface
    super(opts)
    validate_parameters([:trail_name])
    @trail_name = opts[:trail_name]
    catch_aws_errors do
      @resp = @aws.cloudtrail_client.describe_trails({ trail_name_list: [@trail_name] })
      @trail = @resp.trail_list[0].to_h
      @exists = !@trail.empty?
      @s3_bucket_name = @trail[:s3_bucket_name]
      @is_multi_region_trail = @trail[:is_multi_region_trail]
      @trail_arn = @trail[:trail_arn]
      @log_file_validation_enabled = @trail[:log_file_validation_enabled]
      @cloud_watch_logs_role_arn = @trail[:cloud_watch_logs_role_arn]
      @cloud_watch_logs_log_group_arn = @trail[:cloud_watch_logs_log_group_arn]
      @kms_key_id = @trail[:kms_key_id]
      @home_region = @trail[:home_region]
    end
  end

  def delivered_logs_days_ago
    catch_aws_errors do
      begin
        trail_status = @aws.cloudtrail_client.get_trail_status({ name: @trail_name }).to_h
        ((Time.now - trail_status[:latest_cloud_watch_logs_delivery_time]) / (24 * 60 * 60)).to_i unless trail_status[:latest_cloud_watch_logs_delivery_time].nil?
      rescue Aws::CloudTrail::Errors::TrailNotFoundException
        nil
      end
    end
  end

  def logging?
    catch_aws_errors do
      begin
        @aws.cloudtrail_client.get_trail_status({ name: @trail_name }).to_h[:is_logging]
      rescue Aws::CloudTrail::Errors::TrailNotFoundException
        nil
      end
    end
  end

  def encrypted?
    !@kms_key_id.nil?
  end

  def get_log_group_for_multi_region_active_mgmt_rw_all
    return nil if !exists?
    return nil if !@cloud_watch_logs_log_group_arn
    return nil if @cloud_watch_logs_log_group_arn.split(':').count < 6
    return @cloud_watch_logs_log_group_arn.split(':')[6] if has_event_selector_mgmt_events_rw_type_all? && logging?
  end

  def has_event_selector_mgmt_events_rw_type_all?
    event_selector_found = false
    begin
      event_selectors = @aws.cloudtrail_client.get_event_selectors(trail_name: @trail_name)
      event_selectors.event_selectors.each do |es|
        event_selector_found = true if es.read_write_type == 'All' && es.include_management_events == true
      end
    rescue Aws::CloudTrail::Errors::TrailNotFoundException
      event_selector_found
    end
    event_selector_found
  end

  def to_s
    "CloudTrail #{@trail_name}"
  end
end
