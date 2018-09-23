require 'elibri_onix_generator'

module Elibri
  module ONIX
    module Model

      class Product

        class OnixGenerator
           include Elibri::ONIX::Generator
        end


        attr_accessor :product_form_onix_code, :publisher_name, :record_reference, :isbn_value,
                      :authorship_kind, :edition_statement, :thema_codes, :publishing_status_onix_code,
                      :publication_day, :publication_month, :publication_year, :cover_url, :notification_type_onix_code,
                      :collection_name, :collection_part, :title, :subtitle, :title_part, :original_title, :trade_title,
                      :description, :contributors, :height, :width, :thickness, :weight, :number_of_illustrations, :number_of_pages,
                      :cover_type_name, :price_amount, :series_name, :vat, :pkwiu

        def to_xml
          OnixGenerator.new(self, {}).to_s
        end


        def kind_of_book?
          true
        end

        def series_membership_kind 
          if series_name && series_name.size > 0
            "user_given" 
          else
            "no_series"
          end
        end

        def series_memberships
          if series_name && series_name.size > 0
            [OpenStruct.new(series_name: series_name)]
          else
            []
          end
        end

        def collection_with_issn
        end

        def cover_type
          if cover_type_name && cover_type_name.size > 0
            OpenStruct.new(name: cover_type_name)
          end
        end

        def kind_of_measurable?
          width || height
        end


        def title_parts
          res = []
          product_code =  Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::PRODUCT      #01
          collection_code = Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::COLLECTION #02
          res << OpenStruct.new(:level => collection_code, :title => collection_name, :part => self.collection_part) if collection_name && collection_name.size > 0
          res << OpenStruct.new(:level => product_code, :title => self.title, :subtitle => self.subtitle, :part => self.title_part) if self.title && self.title.size > 0
          return res
        end


        def other_texts
          if self.description && self.description.size > 0
              [OpenStruct.new({ :text => description,
                                :type_onix_code => "03",
                                :exportable? => true})]
          else
            []
          end
        end

        def attachments
          if cover_url
            [OpenStruct.new({"onix_resource_mode" => "03", "attachment_type_code" => "01",
                             "file" => OpenStruct.new({ "url" => cover_url })})]
          else
            []
          end
        end


        def notification_type
          OpenStruct.new({"onix_code" => notification_type_onix_code}) if notification_type_onix_code
        end

        def publication_date_with_onix_format_code
          publication_year_str = self.publication_year ? "%04d"% self.publication_year : nil
          publication_month_str = self.publication_month ? "%02d"% self.publication_month : nil
          publication_day_str = self.publication_day ? "%02d"% self.publication_day : nil

          publication_date = [publication_year_str, publication_month_str, publication_day_str].compact.join('')

          if self.publication_year && self.publication_month && self.publication_day
            [publication_year_str + publication_month_str + publication_day_str, Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMMDD]
          elsif self.publication_year && self.publication_month
            [publication_year_str + publication_month_str, Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMM]
          elsif self.publication_year
            [publication_year_str, Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYY]
          else
            [nil, nil]
          end
        end

        def public?
          true
        end

        def publisher_name_for_onix
          publisher_name
        end

        def thema_codes_for_onix
          thema_codes || []
        end

        def initialize(attributes = {})
          attributes.each do |key, value|
            self.send("#{key}=", value)
          end
        end  
      end
    end
  end
end
