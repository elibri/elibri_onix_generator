XML Generator gem used by elibri.

```ruby

class OnixGenerator
  include Elibri::ONIX::Generator
end

book = OpenStruct.new(
  product_form_onix_code: "BC",
  public?: true,
  publisher_name_for_onix: "Czarne",
  record_reference: "6e9b713797aba6a41c0f",
  notification_type: OpenStruct.new(onix_code: Elibri::ONIX::Dict::Release_3_0::NotificationType::ADVANCED_NOTIFICATION),
  isbn_value: "9788380499997",
  title_parts: [
    OpenStruct.new(level: Elibri::ONIX::Dict::Release_3_0:: TitleType::DISTINCTIVE_TITLE,
                   title: "Tragedia na Przełęczy Diatłowa",
                   subtitle: "Historia bez końca")
  ],
  authorship_kind: "user_given",
  edition_statement: "wydanie pierwsze",
  contributors: [
    OpenStruct.new(
      role_onix_code: Elibri::ONIX::Dict::Release_3_0::ContributorRole::AUTHOR,
      generated_full_name: "Alice Lugen",
      name: "Alice",
      last_name: "Lugen",
    ),
  ],
  publishing_status_onix_code:  Elibri::ONIX::Dict::Release_3_0::PublishingStatusCode::FORTHCOMING,
  publication_date_with_onix_format_code: [ "20200415", Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMMDD ],
  attachments: [
    OpenStruct.new(
      onix_resource_mode: Elibri::ONIX::Dict::Release_3_0::ResourceMode::IMAGE,
      attachment_type_code: Elibri::ONIX::Dict::Release_3_0::ResourceContentType::FRONT_COVER,
      updated_at: Time.now,
      url_for_onix: "http://www.elibri.com.pl/system/product_attachments/production/000/157/528/original/3d270120/tragedia_na_przeleczy.jpg"
    ),
  ],
  other_texts: [
    OpenStruct.new(
      text: "<p>\r Pod koniec stycznia 1959 roku grupa turystów...</p>",
      type_onix_code: Elibri::ONIX::Dict::Release_3_0::OtherTextType::MAIN_DESCRIPTION,
      exportable?: true
    )
  ],
  original_title: "",
  languages: [
    OpenStruct.new(
      language_onix_code: "pol",
      role_onix_code: Elibri::ONIX::Dict::Release_3_0::LanguageRole::LANGUAGE_OF_TEXT,
    )
  ],
  kind_of_measurable?: true,
  width: 133,
  height: 215,
  thema_codes_for_onix_with_heading_text: [ "DNP" ],
  series_membership_kind: "user_given",
  series_memberships: [ OpenStruct.new(series_name: "Poza serią") ],
  product_availabilities: [
    OpenStruct.new(
      supplier_role_onix_code: Elibri::ONIX::Dict::Release_3_0::SupplierRole::PUB_TO_RET,
      supplier: OpenStruct.new(name: "Czarne"),
      product_availability_onix_code: Elibri::ONIX::Dict::Release_3_0::ProductAvailabilityType::CONTACT_SUPPLIER,
      price_infos: [
        OpenStruct.new(
          amount: "39.9",
          vat: 5,
          currency_code: "PLN",
        )
      ]
    )
  ]
)


generator = OnixGenerator.new(book, pure_onix: true)
puts generator.to_s

```
