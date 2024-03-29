require "elibri_onix_generator/version"
require 'ostruct'

module Elibri
  module ONIX

    module Generator

      DOC_ORDER = ["record_identifiers", "publishing_status", "product_form", "contributors", "titles", "series_memberships", "measurement",
                    "sale_restrictions", "territorial_rights", "audience_range", "publisher_info", "extent", "edition", "languages", "epub_details",
                    "texts", "supporting_resources", "subjects", "pform_features", "elibri_extensions"]

      DEFAULT_DIALECT = '3.0.1'

      def self.included(base)
        base.extend ClassMethods
      end


      module ClassMethods

        def tag(builder, tag_id, *args, &block)
          builder.__send__(tag_id, *args, &block)
        end


        def render_header(builder, options = {}, &block)
          builder.instruct! :xml, :version=>"1.0", :encoding=>"UTF-8"
          message_attributes = {:release => "3.0", :xmlns => "http://ns.editeur.org/onix/3.0/reference", "xmlns:elibri" => "http://elibri.com.pl/ns/extensions"}
          message_attributes.delete('xmlns:elibri') if options[:pure_onix] || options[:elibri_onix_dialect] == "3.0.2"

          builder.ONIXMessage message_attributes do
            unless options[:pure_onix] || options[:elibri_onix_dialect] == "3.0.2"
              builder.elibri :Dialect, options[:elibri_onix_dialect] || DEFAULT_DIALECT # potrzebne, aby parser wiedział jak interpretować niektóre tagi
            end
            tag(builder, :Header) do
              tag(builder, :Sender) do
                tag(builder, :SenderName, options[:sender_name] || "Elibri.com.pl")
              end
              tag(builder, :SentDateTime, Date.today.strftime("%Y%m%d"))
            end
            yield(builder) if block_given?
          end
        end


        # Zwróć dokumentację dla metod sekcji ONIX z bieżącego pliku. Dzięki temu dokumentacja ONIX jest generowana w locie
        # i nie rozjedzie się z kodem. Dokumentacje można wygenerować tylko dla metod 'def export_XXX!'.
        #
        # Przykład dokumentowania:
        #   # @hidden_tags RecordReference NotificationType
        #   # @title Wymiary produktu
        #   # eLibri zachowuje tylko <strong>wysokość, szerokość, grubość oraz masę produktu.</strong> Dla produktów typu mapa, eksportujemy również jej skalę
        #   # w tagu &lt;MapScale&gt;
        #   def export_measurement!(product)
        #     [...]
        #   end
        #
        #  @hidden_tags określa tagi ONIX, które należy zwinąć w celu zachowania czytelności XML`a.
        #  @title to tytuł sekcji a reszta to wieloliniowy opis.
        #
        #  Dla każdej sekcji trzeba utworzyć odpowiednią metodę w Product::Examples, która zwróci stub produktu.
        #  Np. dla metody 'export_measurement!' w Product::Examples należy utworzyć metodę 'onix_measurement_example'.
        def onix_sections_docs
          # Wczytaj bieżący plik
          code_lines = File.readlines(__FILE__)

          section_docs = Array.new
          # Dla każdej metody o sygnaturze 'def export_NAZWA_SEKCJI!' czytaj otaczające linie komentarzy:
          instance_methods.grep(/export_/).each_with_index do |method_name, section_idx|
            section_docs[section_idx] ||= Hash.new
            section_docs[section_idx][:section_name] = method_name[/export_(.*)!/, 1] # "export_supplier_identifier!" =>  "supplier_identifier"
            section_docs[section_idx][:hidden_tags] = Array.new
            section_docs[section_idx][:auto_render] = true

            # Znajdź numer linii z definicją metody:
            method_definition_line_idx = code_lines.find_index {|line| line.match(/^\s*def #{method_name}/)}

            # Cofamy się w gorę kodu, aż do początku pliku w poszukiwaniu linii zawierającej tag @title w komentarzu.
            (method_definition_line_idx-1).downto(0).each do |line_idx|
              # Oczyść linię kodu ze znaku komentarza i zbędnych spacji:
              line = code_lines[line_idx].strip.sub(/^\s*#\s*/, '#')
              raise "Nieprawidłowy format dokumentacji dla metody #{method_name}" if line.match(/^end$/)
              if md = line.match(/^\s*$/)
                break
              elsif md = line.match(/@render (.*)$/)
                section_docs[section_idx][:auto_render] = false
                render_call = "\n= render :partial => 'example', :locals => { :method => '#{md[1].strip}' }\n"
                section_docs[section_idx][:description] = [render_call, section_docs[section_idx][:description]].join("\n")
              elsif md = line.match(/@title (.*)$/)
                section_docs[section_idx][:section_title] = md[1].gsub(/^#/, '')
              elsif md = line.match(/@hidden_tags (.*)$/)
                section_docs[section_idx][:hidden_tags] = md[1].gsub(/^#/, '').scan(/\w+/)
              elsif line == '#'
                section_docs[section_idx][:description] = ["\n%br/\n", section_docs[section_idx][:description]].join("\n")
              else
                section_docs[section_idx][:description] = [line.gsub(/^#/, ''), section_docs[section_idx][:description]].join("\n")
              end
            end
          end
          # Zwróć posortowane według kolejności sekcji:
          section_docs.find_all { |section_hash| DOC_ORDER.index(section_hash[:section_name]) }.sort_by {|section_hash|  DOC_ORDER.index(section_hash[:section_name]) }
        end
      end


      def initialize(products, options = {})
        @options = options
        @options[:export_headers] =  true unless options.has_key?(:export_headers)
        @options[:elibri_onix_dialect] = DEFAULT_DIALECT unless options.has_key?(:elibri_onix_dialect)
        @options[:comments] = false unless options.has_key?(:comments)
        @options[:xml_variant] = OpenStruct.new(blank?: false,
                                               includes_basic_meta?: true,
                                               includes_other_texts?: true,
                                               includes_media_files?: true,
                                               includes_stocks?: true) unless options.has_key?(:xml_variant)

        @xml_variant = options[:xml_variant]
        raise ":xml_variant unspecified" if @xml_variant.blank?

        if products.respond_to?(:to_ary)
          @products = products.to_ary
        else
          @products = [products]
        end
        @comments = options[:comments]
        @comment_kinds = options[:comment_kinds]
        @out = []
        @builder = Builder::XmlMarkup.new(:indent => 2, :target => @out)
        @elibri_onix_dialect = options[:elibri_onix_dialect]
        # Gdy true, ignorujemy rozszerzenia eLibri
        @pure_onix = options[:pure_onix] || options[:elibri_onix_dialect]  == '3.0.2'
        @skip_sourcename_and_timestamp = !!options[:skip_sourcename_and_timestamp]
        @sender_name = options[:sender_name]
        @lan = options[:lan] || "pol"
      end

      def onix
        # W testach często nie chcę żadnych nagłówków - interesuje mnie tylko tag <Product>
        if @options[:export_headers]
          self.class.render_header(@builder, elibri_onix_dialect: @elibri_onix_dialect, pure_onix: @pure_onix || !@xml_variant.includes_basic_meta?, sender_name: @sender_name) do
            render_products!
          end
        else
          render_products!
        end
        @out.join
      end

      def elibri_extensions
        @products.each do |product|
          export_elibri_extensions!(product)
        end
        @out.join
      end


      protected

        # Wstaw do XML`a komentarz
        def comment(text, options = {})
          if options[:kind] && @comment_kinds
            Array(options[:kind]).each do |kind|
              @builder.comment!("$#{kind}$ #{text}")
            end
          elsif @comments
            @builder.comment!(text)
          end
        end

        def field_exists?(object, method_name)
          if object.respond_to?(method_name)
            v = object.send(method_name)
            v = v.strip if v.respond_to?(:strip)
            v && (v.respond_to?(:size) ? v.size > 0 : true)
          else
            false
          end
        end


        def comment_dictionary(description, dict, options = {})
          indent = options[:indent] || 4
          pretty_string = lambda {|dict_item| "\n" + " " * indent + "#{dict_item.onix_code} - #{dict_item.name}" }
          case dict
            when Symbol
              dictionary_items = Elibri::ONIX::Dict::Release_3_0.const_get(dict)::ALL.map(&pretty_string)
            when Array
              dictionary_items = dict.map {|dict_item| "\n" + " " * indent + dict_item }
          end

          comment(description + dictionary_items.join, options)
        end


        def render_products!
          @products.each do |product|
            next unless product.public?

            tag(:Product) do
              export_record_identifiers!(product) #PR.1 + PR.2
              if @xml_variant.includes_basic_meta?
                tag(:DescriptiveDetail) do
                  export_product_form!(product) #PR.3
                  export_epub_details!(product) #PR.3
                  export_pform_features!(product)
                  export_measurement!(product)
                  export_country_of_manufacture!(product)
                  export_classification!(product)
                  #jak się dodaje tytuł, który nie jest samodzielne w sprzedaży?
                  #jak się dodaje tytuł, który zostanie przeceniony?
                  export_series_memberships!(product) #P.5
                  export_titles!(product) #PR.6
                  export_contributors!(product) #PR.7
                  #PR.8 - konferencje
                  export_edition!(product) #PR.9
                  export_languages!(product) #PR.10
                  export_extent!(product) #PR.11
                  export_subjects!(product) #PR.12
                  export_audience!(product) if field_exists?(product, :onix_audience_code_value)
                  export_audience_range!(product) if product.respond_to?(:audience_range_present?) && product.audience_range_present? #PR.13
                end
              end
              if @xml_variant.includes_other_texts? || @xml_variant.includes_media_files?
                tag(:CollateralDetail) do
                  if @xml_variant.includes_other_texts? #TODO zmienić nazwę wariantu
                    export_texts!(product) #PR.14
                  end
                  #P.15 - citywany kontent - sprawdzić
                  if @xml_variant.includes_media_files?
                    export_supporting_resources!(product) #PR.16 #TODO - to jest też do przerobienia
                  end
                  #P.17 - nagrody
                end
              end
              remove_tag_if_empty!(:CollateralDetail)
              #P.18 - ContentItem

              if @xml_variant.includes_basic_meta?
                tag(:PublishingDetail) do
                  export_publisher_info!(product) #P.19
                  export_publishing_status!(product) #PR.20
                  export_territorial_rights!(product)
                  export_sale_restrictions!(product) if product.respond_to?(:sale_restricted?) && product.sale_restricted? #PR.21
                end
                remove_tag_if_empty!(:PublishingDetail)

                #P.23 - related products
                if field_exists?(product, :facsimiles_for_onix)
                  export_related_products!(product)
                end

                export_masters_info!(product)
              end
              #P.24 - Market
              #P.25 - market representation
              if @xml_variant.includes_stocks?
                export_supply_details!(product) #PR.26
              end

              #fake dla exportu ze sklepu - w elibri ten kod nie zadziała
              # if @xml_variant.respond_to?(:cover_price?) && @xml_variant.cover_price?
              #   export_cover_price!(product) #fake, żeby jakoś te dane wysłać
              # end
              if @xml_variant.includes_basic_meta?
                export_elibri_extensions!(product) unless @pure_onix
              end
            end
          end
        end


        # Renderuj tag w XML`u za pomocą Buildera. Jeśli wybrano opcję krótkich tagów,
        # wstaw krótki tag z hasha SHORT_TAGS.
        def tag(tag_id, *args, &block)
          self.class.tag(@builder, tag_id, *args, &block)
        end

        def remove_tag_if_empty!(tag_name)
          idx = @out.rindex("<#{tag_name}")
          if idx
            tail = @out[idx..-1].join.strip.gsub("\n", "").gsub(" ", "")
            if tail == "<#{tag_name}></#{tag_name}>" #wycinaj końcówkę
              (@out.size - idx + 1).times do #zmieniaj listę in-place
                @out.pop
              end
            end
          end
        end

        # @hidden_tags NotificationType DescriptiveDetail ProductSupply PublishingDetail
        # @title Identyfikatory rekordu
        # Każdy rekord w ONIX-ie posiada wewnętrzny identyfikator, który jest dowolnym ciągiem znaków, i jest przekazywany
        # w tagu <strong>&lt;ProductIdentifier&gt;</strong>. Gwarantowana jest jego niezmienność.
        #
        #
        # Oprócz tego każdy produkt może posiadać numer ISBN, EAN oraz jeden lub więcej identyfikatorów dostawców (np. numer w bazie Olesiejuka)
        # Tutaj już nie ma gwarancji niezmienności, choć jest to bardzo rzadka sytuacja (np. wydrukowany został jednak inny numer ISBN na okładce,
        # i wydawcnictwo zmienia wpis w eLibri)
        def export_record_identifiers!(product)
          comment 'Unikalne ID rekordu produktu', :kind => :onix_record_identifiers
          tag(:RecordReference, product.record_reference) #doc
          comment_dictionary "Typ powiadomienia", :NotificationType, :kind =>  :onix_publishing_status
          tag(:NotificationType, product.notification_type.onix_code) # Notification confirmed on publication - Lista 1
          if field_exists?(product, :deletion_text)
            comment "Występuje tylko gdy NotificationType == #{Elibri::ONIX::Dict::Release_3_0::NotificationType::DELETE}", :kind => :onix_record_identifiers
            tag(:DeletionText, product.deletion_text)
          end
          if field_exists?(product, :record_source_name)
            tag(:RecordSourceName, product.record_source_name)
          end

          if field_exists?(product, :isbn_value)
            comment 'ISBN', :kind => :onix_record_identifiers
            tag(:ProductIdentifier) do
              tag(:ProductIDType, Elibri::ONIX::Dict::Release_3_0::ProductIDType::ISBN13) #lista 5
              tag(:IDValue, product.isbn_value)
            end
          end

          if field_exists?(product, :ean) && product.ean != product.isbn_value
            comment 'EAN-13 - gdy inny niż ISBN', :kind => :onix_record_identifiers

            tag(:ProductIdentifier) do
              tag(:ProductIDType, Elibri::ONIX::Dict::Release_3_0::ProductIDType::EAN)
              tag(:IDValue, product.ean)
            end
          end

          if field_exists?(product, :doi)
            tag(:ProductIdentifier) do
              tag(:ProductIDType, Elibri::ONIX::Dict::Release_3_0::ProductIDType::DOI)
              tag(:IDValue, product.doi)
            end
          end

          if product.respond_to?(:external_identifier) && product.external_identifier
            tag(:ProductIdentifier) do
              tag(:ProductIDType, Elibri::ONIX::Dict::Release_3_0::ProductIDType::PROPRIETARY) #lista 5
              tag(:IDTypeName, product.external_identifier.type_name)
              tag(:IDValue, product.external_identifier.value)
            end
          end

          if @xml_variant.includes_stocks?
            if product.respond_to?(:product_availabilities)
              product.product_availabilities.each do |pa|
                if field_exists?(pa, :supplier_identifier)
                  comment "Identyfikator dostawcy: #{pa.supplier.name}", :kind => :onix_record_identifiers
                  tag(:ProductIdentifier) do
                    tag(:ProductIDType, Elibri::ONIX::Dict::Release_3_0::ProductIDType::PROPRIETARY) #lista 5
                    tag(:IDTypeName, pa.supplier.name)
                    tag(:IDValue, pa.supplier_identifier)
                  end
                end
              end
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier TitleDetail
        # @title Forma produktu
        # <strong>&lt;ProductForm&gt;</strong> określa typ produktu. Np. BA to książka.<br/>
        # <strong>&lt;ProductComposition&gt;</strong> przybiera aktualnie zawsze wartość 00 - czyli że przedmiotem handlu jest pojedyncza książka.
        # W przyszłości ulegnie to zmianie, gdy dodamy do eLibri obsługę pakietów książek. Pakiet książek to komplet kilku książek,
        # z nowym numerem ISBN, i nową ceną, na ogół niższą, niż suma cen książek zawartych w pakiecie.
        def export_product_form!(product)
          comment 'W tej chwili tylko 00 - pojedynczy element', :kind => :onix_product_form
          tag(:ProductComposition, Elibri::ONIX::Dict::Release_3_0::ProductComposition::SINGLE_COMPONENT_RETAIL_PRODUCT) #lista 2

          if @elibri_onix_dialect == "3.0.1" || !product.respond_to?(:product_form_for_3_0_2)
            if product.product_form_onix_code
              comment_dictionary "Format produktu", :ProductFormCode, :indent => 10, :kind => [:onix_product_form]
              tag(:ProductForm, { "PODH" => "BB", "PODS" => "BC", "OPEN_ACCESS" => "EA" }[product.product_form_onix_code] || product.product_form_onix_code)
            end
          elsif @elibri_onix_dialect == "3.0.2"
            if product.product_form_onix_code
              product_form, product_form_detail = product.product_form_for_3_0_2
              tag(:ProductForm, product_form)
              tag(:ProductFormDetail,  product_form_detail) if product_form_detail
            end
          else
            raise ArgumentError, "Unknow dialect: #{@elibri_onix_dialect}"
          end
        end

        # @hidden_tags RecordReference NotificationType ProductIdentifier TitleDetail PublishingDetail ProductComposition
        # @title E-booki
        # <strong>&lt;EpubTechnicalProtection&gt;</strong> Określa typ zabezpieczenia stosowanego przy publikacji e-booka.<br/>
        #
        # <strong>&lt;ProductFormDetail&gt;</strong> zawiera format w jakim rozprowadzany jest e-book.
        # Aktualnie może przyjąć wartości takie jak:
        # #{Elibri::ONIX::Dict::Release_3_0::ProductFormDetail::ALL.map(&:name).to_sentence(:last_word_connector => ' lub ')}<br/>
        #
        # @render onix_epub_details_example
        # <br/>
        # Wydawnictwa podają też w systemie eLibri informację, czy prawo do sprzedaży ebook-a jest bezterminowe.
        # W takim przypadku w opisie produktu wystąpi pusty tag <strong>&lt;elibri:SaleNotRestricted&gt;</strong> (ostatnie trzy przykłady).<br/><br/>
        # Jeśli wydawca posiada licencję na określony czas, to w opisie produktu wystąpi tag
        # <strong>&lt;elibri:SaleRestrictedTo&gt;</strong>, w którym będzie podana data wygaśnięcia licencji (w formacie YYYYMMDD).
        # Przykład użycia w pierwszym przykładzie.
        #
        def export_epub_details!(product)
          if field_exists?(product, :product_form_detail_onix_codes)  #lista 175
            comment_dictionary "Dostępne formaty produktu", :ProductFormDetail, :indent => 10, :kind => :onix_epub_details
            product.product_form_detail_onix_codes.each do |onix_code|
              tag(:ProductFormDetail, onix_code)
            end
          end

          if product.respond_to?(:digital?) && product.digital?
            if field_exists?(product, :epub_technical_protection_onix_codes)
              comment_dictionary "Zabezpieczenie", :EpubTechnicalProtection, :indent => 10, :kind => :onix_epub_details
              product.epub_technical_protection_onix_codes.each do |code|
                tag(:EpubTechnicalProtection, code)
              end
            end
          end

          if field_exists?(product, :epub_license)
            tag(:EpubLicense) do
              tag(:EpubLicenseName, product.epub_license.name)
              if field_exists?(product.epub_license, :url)
                tag(:EpubLicenseExpression) do
                  tag(:EpubLicenseExpressionType, Elibri::ONIX::Dict::Release_3_0::EpubLicenseExpressionType::HUMAN_READABLE)
                  tag(:EpubLicenseExpressionLink, product.epub_license.url)
                end
              end
            end
          end
        end

        # @hidden_tags RecordReference NotificationType ProductIdentifier ProductComposition TitleDetail PublishingDetail ProductSupply
        # @title Gry planszowe i puzzle
        # Gry planszowe i puzlle mogą zawierać dodatkowe informacje o ilości elementów (puzzli) w pudełku, czasie gry oraz dopuszczalnej ilości graczy.
        # Każda z tych informacji jest umieszczna w blocku &lt;ProductFormFeature&gt;, w którym &lt;ProductFormFeatureType&gt; określa typ wartości,
        # a sama wartość jest umieszczona w tagu &lt;ProductFormFeatureValue&gt; (wartość liczbowa) lub w tagu &lt;ProductFormFeatureDescription&gt;
        # (przedział wartości)
        def export_pform_features!(product)

          if product.respond_to?(:number_of_pieces) && product.number_of_pieces
            tag(:ProductFormFeature) do
              comment_dictionary 'Typ warrtości', :ProductFormFeatureType, :indent => 10, :kind => :onix_pform_features

              tag(:ProductFormFeatureType, Elibri::ONIX::Dict::Release_3_0::ProductFormFeatureType::NUMBER_OF_GAME_PIECES)
              tag(:ProductFormFeatureValue, product.number_of_pieces)
            end
          end

          if product.respond_to?(:players_number_from) && product.respond_to?(:players_number_to)
            players = [product.players_number_from, product.players_number_to].compact.uniq.sort
            if players.present?
              tag(:ProductFormFeature) do
                comment_dictionary 'Typ wartości', :ProductFormFeatureType, :indent => 10, :kind => :onix_pform_features

                tag(:ProductFormFeatureType, Elibri::ONIX::Dict::Release_3_0::ProductFormFeatureType::GAME_PLAYERS)
                if players.size == 1
                  tag(:ProductFormFeatureValue, players.first)
                else
                  tag(:ProductFormFeatureDescription, "#{players.first}-#{players.last} graczy")
                end
              end
            end
          end

          if product.respond_to?(:playing_time_from) && product.respond_to?(:playing_time_to)
            ptime = [product.playing_time_from, product.playing_time_to].compact.uniq.sort
            if ptime.present?
              tag(:ProductFormFeature) do
                comment_dictionary 'Typ wartości', :ProductFormFeatureType, :indent => 10, :kind => :onix_pform_features

                tag(:ProductFormFeatureType, Elibri::ONIX::Dict::Release_3_0::ProductFormFeatureType::GAME_PLAY_TIME)
                if ptime.size == 1
                  tag(:ProductFormFeatureValue, ptime.first)
                else
                  tag(:ProductFormFeatureDescription, "#{ptime.first}-#{ptime.last} min.")
                end
              end
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier ProductComposition ProductForm TitleDetail
        # @title Wymiary produktu
        # Następujące atrybuty są udostępniane:  wysokość, szerokość, grubość oraz masę produktu. Pierwsze trzy podajemy zawsze w milimetrach, masę w gramach.
        # W przypadku map eksportujemy również jej skalę w tagu &lt;MapScale&gt;
        def export_measurement!(product)

          if product.respond_to?(:kind_of_measurable?) && product.kind_of_measurable?
            [[product.height,    Elibri::ONIX::Dict::Release_3_0::MeasureType::HEIGHT, 'mm', 'Wysokość'],
             [product.width,     Elibri::ONIX::Dict::Release_3_0::MeasureType::WIDTH, 'mm', 'Szerokość'],
             [product.thickness, Elibri::ONIX::Dict::Release_3_0::MeasureType::THICKNESS, 'mm', 'Grubość'],
             [product.weight,    Elibri::ONIX::Dict::Release_3_0::MeasureType::WEIGHT, 'gr', 'Masa']
            ].each do |value, measure_type_code, unit_code, name|
               if value
                 tag(:Measure) do
                   comment "#{name}: #{value}#{unit_code}", :kind => :onix_measurement
                   tag(:MeasureType, measure_type_code) #lista 48
                   tag(:Measurement, value)
                   tag(:MeasureUnitCode, unit_code)
                 end
               end
            end

            if product.respond_to?(:kind_of_map?) && product.respond_to?(:map_scale) && product.kind_of_map? and product.map_scale
              comment 'Skala mapy - tylko dla produktów typu mapa'
              tag(:MapScale, product.map_scale)
            end
          end
        end

        def export_country_of_manufacture!(product)

          if field_exists?(product, :country_of_manufacture)
            tag(:CountryOfManufacture, product.country_of_manufacture)
          end

        end

        def export_classification!(product)

          if field_exists?(product, :pkwiu)
            tag(:ProductClassification) do
              tag(:ProductClassificationType, Elibri::ONIX::Dict::Release_3_0::ProductClassificationType::PKWIU)
              tag(:ProductClassificationCode, product.pkwiu)
            end
          end

          if field_exists?(product, :cn_code)
            tag(:ProductClassification) do
              tag(:ProductClassificationType, Elibri::ONIX::Dict::Release_3_0::ProductClassificationType::CN)
              tag(:ProductClassificationCode, product.cn_code)
            end
          end

        end


        # @hidden_tags ProductIdentifier DescriptiveDetail ProductSupply
        # @title Cykl życia rekordu
        # W ONIX-ie status rekordu jest reprezentowany za pomocą kombinacji tagów <strong>&lt;NotificationType&gt;</strong> i <strong>&lt;PublishingStatus&gt;</strong>
        #
        #
        # Tuż po założeniu przez wydawnictwo każdy rekord ma status prywatny. Jest to wtedy widoczny tylko i wyłącznie dla pracowników wydawnictwa,
        # i nie jest udostępniany na zewnątrz. Po wypełnieniu kilku podstawowych danych (autor, tytuł) pracownik wydawnictwa może zmienić status
        # rekordu na <i>zapowiedź</i>. W tym przypadku wartość <strong>&lt;NotificationType&gt;</strong> to 01 - wczesne powiadomienie.
        #
        # @render onix_announced_product_example
        #
        # Po uzupełnieniu większości danych niezbędnych (okładka, cena, ISBN, okładka, dokładna data premiery) wydawnictwo może zmienić
        # status rekordu na <i>przedsprzedaż</i>.
        # W zależności od naszego poziomu zaufania do terminowości wydawnictwa można uruchomić dla takiego tytułu przedsprzedaż na stronie księgarni.
        # Wydawnictwo może zmienić datę premiery, jeśli produkt znajduje się w przedsprzedaży, warto zaimplementować procedurę poinformowania klientów
        # o zmianie.
        # Rekord o takim statusie ma wartość 02 w <strong>&lt;NotificationType&gt;</strong>
        #
        # @render onix_preorder_product_example
        #
        # Po ukazaniu się książki jej status zostaje zmieniony na <i>dostępna na rynku</i>.
        # Rekord o takim statusie ma wartość 03 w <strong>&lt;NotificationType&gt;</strong> i 04 w <strong>&lt;PublishingDetail&gt;</strong>
        #
        # @render onix_published_product_example
        #
        # Każde wydawnictwo oczywiście liczy na to, że nakład książki się wyprzeda. Bardzo trudno jest poprawnie zdefiniować, co oznacza wyczerpany nakład.
        # Bardzo długo egzemplarze książki, której nie ma już w magazynie wydawnictwa, mogą znajdować się w księgarniach i być zwracane co jakiś czas do hurtowni,
        # co powoduje, że dany tytuł będzie się stawał na jakiś czas dostępny. W związku z tym informacje o wyczerpaniu się nakładu podejmuje wydawnictwo, i oznacza
        # to, że nie będzie akceptować zamówień na określony tytuł. Nie oznacza to jednak, że tytuł jest w ogóle niedostępny, w dalszym ciągu może być w ofercie
        # hurtowni.
        # Rekord o statusie <i>nakład wyczerpany</i> ma wartość 03 w <strong>&lt;NotificationType&gt;</strong> i 07 w <strong>&lt;PublishingDetail&gt;</strong>
        #
        # @render onix_out_of_print_product_example
        #
        # Status 08 (niedostępny) w <strong>&lt;PublishingDetail&gt;</strong> nie jest w tej chwili używany przez eLibri. W przyszłości proszę się spodziewać również
        # dodania informacji o dodrukach realizowanych pod tym samym numerem ISBN.
        #
        def export_publishing_status!(product)
          if product.publishing_status_onix_code
            comment_dictionary 'Status publikacji', :PublishingStatusCode, :indent => 10, :kind => :onix_publishing_status
            tag(:PublishingStatus, product.publishing_status_onix_code) #lista 64 #TODO sprawdzić
          end

          #TODO - tu można również zawrzeć datę, przed którą produkt nie może być importowany do baz sklepów
          date, format_code = product.publication_date_with_onix_format_code
          if date && format_code
            tag(:PublishingDate) do
              comment 'Jeśli 01 - data publikacji', :kind => :onix_publishing_status
              tag(:PublishingDateRole, Elibri::ONIX::Dict::Release_3_0::PublishingDateRole::PUBLICATION_DATE) #lista 163
              comment_dictionary "Format daty", :DateFormat, :indent => 12, :kind => :onix_publishing_status
              tag(:DateFormat, format_code) if @elibri_onix_dialect == '3.0.1' #lista 55
              tag(:Date, date, dateformat: format_code)
            end
          end

          if product.respond_to?(:distribution_start) && product.distribution_start
            tag(:PublishingDate) do
              comment "Jeśli 27 - to data początku przyjmowania zamówień na dany tytuł"
              tag(:PublishingDateRole, Elibri::ONIX::Dict::Release_3_0::PublishingDateRole::PREORDER_EMBARGO_DATE) #lista 163
              tag(:DateFormat, Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMMDD) if @elibri_onix_dialect == '3.0.1'
              tag(:Date, product.distribution_start.strftime("%Y%m%d"), dateformat: Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMMDD)
            end
          end

          if product.respond_to?(:epub_sale_not_restricted?) && product.respond_to?(:epub_sale_restricted_to)
            if !product.epub_sale_not_restricted? && product.epub_sale_restricted_to_for_onix
              tag(:PublishingDate) do
                comment "Jeśli 13 - to data po której książka zostanie wycofana z rynku"
                tag(:PublishingDateRole, Elibri::ONIX::Dict::Release_3_0::PublishingDateRole::OUT_OF_PRINT_DATE) #lista 163
                tag(:DateFormat, Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMMDD) if @elibri_onix_dialect == '3.0.1'
                tag(:Date, product.epub_sale_restricted_to_for_onix.strftime("%Y%m%d"), dateformat: Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMMDD)
              end
            end
          end
        end

        # @hidden_tags RecordReference NotificationType ProductIdentifier DescriptiveDetail Publisher PublishingStatus
        # @title Terytorialne ograniczenia sprzedaży.
        # W tej chwili w systemie eLibri można zastrzec, że sprzedaż książek/ebooków jest ograniczona do terenu Polski,
        # albo pozwolić na sprzedaż na całym świecie. Poniżej dwa przykłady, jeden dla wyłączości na terenie Polski, drugi
        # dopuszczający sprzedaż na całym świecie. Informacja o ograniczeniu jest zawarta w obręcie <strong>&lt;SalesRights&gt;</strong>
        def export_territorial_rights!(product)
          if product.respond_to?(:sale_restricted_to_poland?)
            if !(product.respond_to?(:unpriced_item?) && product.unpriced_item?)
              tag(:SalesRights) do
                comment "Typ restrykcji - sprzedaż tylko w wymienionym kraju, regionie, zawsze '01'", :kind => :onix_territorial_rights
                tag(:SalesRightsType, Elibri::ONIX::Dict::Release_3_0::SalesRightsType::FOR_SALE_WITH_EXLUSIVE_RIGHTS)
                tag(:Territory) do
                  if product.sale_restricted_to_poland?
                    tag(:CountriesIncluded, "PL")
                  else
                    tag(:RegionsIncluded, "WORLD")
                  end
                end
              end
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier DescriptiveDetail
        # @title Ograniczenia sprzedaży
        # eLibri umożliwia przechowywanie informacji o ograniczaniach dotyczących sprzedaży produktu.
        # Obecnie obsługuje tylko 1 typ ograniczenia: wyłączność na produkt dla określonego detalisty.
        # Opcjonalnie może się też pojawić data wygaśnięcia ograniczenia - w innym przypadku oznacza to, że produkt został przeznaczony tylko
        # dla jednej, określonej sieci.
        # W przypadku, gdy jest podana data wyłączności na sprzedaż produktu, należy ją traktować jako faktyczną datę premiery.
        def export_sale_restrictions!(product)
          if product.sale_restricted?
            tag(:SalesRestriction) do
              #lista 71 - For sale only through designated retailer, though not under retailer's own brand/imprint.
              comment "Typ restrykcji - używamy tylko #{Elibri::ONIX::Dict::Release_3_0::SalesRestrictionType::RETAILER_EXCLUSIVE} (sprzedaż tylko poprzez wybranego detalistę)", :kind => :onix_sale_restrictions
              tag(:SalesRestrictionType, Elibri::ONIX::Dict::Release_3_0::SalesRestrictionType::RETAILER_EXCLUSIVE)
              if field_exists?(product, :sale_restricted_for)
                tag(:SalesOutlet) do
                  tag(:SalesOutletName, product.sale_restricted_for)
                end
              end
              comment "Ograniczenie wygasa #{product.sale_restricted_to.strftime("%d.%m.%Y")}", :kind => :onix_sale_restrictions
              tag(:EndDate, product.sale_restricted_to.strftime("%Y%m%d"))
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier ProductComposition ProductForm TitleDetail
        # @title Wiek czytelnika
        # Zarówno wiek 'od', jak i wiek 'do' są opcjonalne.
        def export_audience_range!(product)
          if product.audience_age_from
            tag(:AudienceRange) do
              comment "Ograniczenie dotyczy wieku czytelnika - zawsze #{Elibri::ONIX::Dict::Release_3_0::AudienceRangeQualifier::READING_AGE}", :kind => :onix_audience_range
              tag(:AudienceRangeQualifier, Elibri::ONIX::Dict::Release_3_0::AudienceRangeQualifier::READING_AGE)
              comment "Wiek od #{product.audience_age_from} lat", :kind => :onix_audience_range
              tag(:AudienceRangePrecision, Elibri::ONIX::Dict::Release_3_0::AudienceRangePrecision::FROM)
              tag(:AudienceRangeValue, product.audience_age_from)
            end
          end

          if product.audience_age_to
            tag(:AudienceRange) do
              comment "Ograniczenie dotyczy wieku czytelnika - zawsze #{Elibri::ONIX::Dict::Release_3_0::AudienceRangeQualifier::READING_AGE}", :kind => :onix_audience_range
              tag(:AudienceRangeQualifier, Elibri::ONIX::Dict::Release_3_0::AudienceRangeQualifier::READING_AGE)
              comment "Wiek do #{product.audience_age_to} lat", :kind => :onix_audience_range
              tag(:AudienceRangePrecision, Elibri::ONIX::Dict::Release_3_0::AudienceRangePrecision::TO)
              tag(:AudienceRangeValue, product.audience_age_to)
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier DescriptiveDetail
        # @title Informacje o wydawcy
        # W rekordzie znajduje się oczywiście nazwa wydawnictwa. Wydawca może określić też imprint oraz miasto, w którym została wydana ksiażka.
        # Z imprintem mamy do czynienia wtedy, gdy książki są wydawane pod różnymi markami, pula ISBN jest jednak wspólna.
        # Jeśli wydawnictwo uzupełnia nazwę imprintu, to powinna być ona traktowana jako nazwa wydawnictwa przy prezentacji
        # książki klientowi końcowemu.
        def export_publisher_info!(product)
          if product.respond_to?(:imprint_for_onix) && product.imprint_for_onix
            tag(:Imprint) do
              comment "Nazwa imprintu", :kind => :onix_publisher_info
              tag(:ImprintName, product.imprint_for_onix.name)
            end
          end

          if product.respond_to?(:publisher_name_for_onix) && product.publisher_name_for_onix
            tag(:Publisher) do
              comment "Wydawca - używamy tylko kodu 01 (główny wydawca)", :kind => :onix_publisher_info
              tag(:PublishingRole, '01') # Publisher, lista 45 #TODO jeszcze może być współwydawca
              if product.respond_to?(:publisher_id_for_onix)
                tag(:PublisherIdentifier) do
                  tag(:PublisherIDType, '01') #prioprietary
                  tag(:IDTypeName, 'ElibriPublisherCode')
                  tag(:IDValue, product.publisher_id_for_onix)
                end
              end
              tag(:PublisherName, product.publisher_name_for_onix)
              if product.respond_to?(:publisher_product_url) && product.publisher_product_url.present?
                tag(:Website) do
                  tag(:WebsiteRole, Elibri::ONIX::Dict::Release_3_0::WebsiteRole::PUBLISHER_WEBPAGE_FOR_SPECIFIED_WORK)
                  tag(:WebsiteLink, product.publisher_product_url)
                end
              end
            end
          end

          if field_exists?(product, :city_of_publication)
            tag(:CityOfPublication, product.city_of_publication)
          elsif product.respond_to?(:publisher) && product.publisher.city && product.publisher.city.size > 0
            tag(:CityOfPublication, product.publisher.city)
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier ProductComposition ProductForm TitleDetail
        # @title Pozostałe atrybuty
        # Dodatkowo każdy produkt może mieć kilka dodatkowych atrybutów: wielkość pliku (w Mb, tylko e-book),
        # czas trwania (tylko audiobook, w minutach), ilość stron, ilość ilustracji.
        #
        # Poniżej przykład dla e-booka (wielkość pliku, ilość stron i ilustracji)
        # @render onix_ebook_extent_example
        #
        # I przykład dla audiobook-a, z czasem trwania nagrania:
        # @render onix_audiobook_extent_example
        def export_extent!(product)
          if product.respond_to?(:digital?) && product.respond_to?(:file_size) && product.digital? and product.file_size
            tag(:Extent) do
              comment 'Rozmiar pliku (w MB) - tylko dla produktów cyfrowych (e-book, audiobook)', :kind => :onix_extent
              tag(:ExtentType, Elibri::ONIX::Dict::Release_3_0::ExtentType::FILE_SIZE)
              tag(:ExtentValue, product.file_size)
              comment 'W MB', :kind => :onix_extent
              tag(:ExtentUnit, Elibri::ONIX::Dict::Release_3_0::ExtentUnit::MEGABYTES)
            end
          end

          if product.respond_to?(:kind_of_audio?) && product.respond_to?(:duration) && product.kind_of_audio? and product.duration && product.duration.to_i > 0
            tag(:Extent) do
              comment 'Czas trwania (w minutach) - tylko dla produktów typu audio', :kind => :onix_extent
              tag(:ExtentType, Elibri::ONIX::Dict::Release_3_0::ExtentType::DURATION)
              tag(:ExtentValue, product.duration)
              comment 'W minutach', :kind => :onix_extent
              tag(:ExtentUnit, Elibri::ONIX::Dict::Release_3_0::ExtentUnit::MINUTES)
            end
          end

          if field_exists?(product, :number_of_pages) && product.number_of_pages.to_i > 0
            tag(:Extent) do
              comment 'Liczba stron - tylko dla produktów typu książka', :kind => :onix_extent
              tag(:ExtentType, Elibri::ONIX::Dict::Release_3_0::ExtentType::PAGE_COUNT)
              tag(:ExtentValue, product.number_of_pages)
              tag(:ExtentUnit, Elibri::ONIX::Dict::Release_3_0::ExtentUnit::PAGES)
            end
          end
          if field_exists?(product, :number_of_illustrations) && product.number_of_illustrations.to_i > 0
            comment 'Liczba ilustracji - tylko dla produktów typu książka', :kind => :onix_extent
            tag(:NumberOfIllustrations, product.number_of_illustrations)
          end
        end


        def export_audience!(product)
          tag(:Audience) do
            tag(:AudienceCodeType, Elibri::ONIX::Dict::Release_3_0::AudienceCodeType::ONIX)
            tag(:AudienceCodeValue, product.onix_audience_code_value)
          end
        end

        # @hidden_tags RecordReference NotificationType ProductIdentifier ProductComposition ProductForm TitleDetail
        # @title Kategorie
        # W dostarczanych przez nas plikach ONIX mogą być zawarte dwa rodzaje kategoryzacji:
        # <ul>
        #   <li>Thema - <a href='https://www.elibri.com.pl/thema'>browser kategorii</a>, <a href='https://www.elibri.com.pl/system/doc/thema-przyklady.pdf'>przykłady</a>,
        #       <a href='https://www.editeur.org/151/Thema/'>oficjalna strona Themy</a>
        #   <li>kategoryzacja wydawnicza</li>
        #   <li>słowa kluczowe (tagi)
        #   </li>
        # </ul>
        # Te kategoryzacje mogą współistnieć, rozróżniane przez wartości w &lt;SubjectSchemeIdentifier&gt; i  &lt;SubjectSchemeName&gt;:
        # <ul>
        #   <li>&lt;SubjectSchemeIdentifier&gt; o wartościach 93 - 99 - to są kategorie i kwantyfikatory Thema
        #   <li>&lt;SubjectSchemeIdentifier&gt; o wartości 24 oraz &lt;SubjectSchemeName&gt; z nazwą wydawnictwa - to są kategorie wydawnicze.</li>
        #   <li>&lt;SubjectSchemeIdentifier&gt; o wartości 20 - w polu &lt;SubjectHeadingText&gt; są słowa kluczowe rozdzielone średnikiem.</li>
        # </ul>
        def export_subjects!(product)

          if product.respond_to?(:thema_codes_for_onix_with_heading_text)
            product.thema_codes_for_onix_with_heading_text.each do |code, text|

              scheme_id = {
                    "1" => 94,  #Thema place qualifier
                    "2" => 95,  #Thema language qualifier
                    "3" => 96,  #Thema time period qualifier
                    "4" => 97,  #Thema educational purpose qualifier
                    "5" => 98,  #Thema interest age / special interest qualifier
                    "6" => 99,  #Thema style qualifier
                }[code[0]] || 93

              tag(:Subject) do
                tag(:SubjectSchemeIdentifier, scheme_id)
                tag(:SubjectSchemeVersion, Elibri::ONIX::ThemaVersion)
                tag(:SubjectCode, code)
                tag(:SubjectHeadingText, text) if text && text.size > 0
              end
            end
          end

          # Kategorie wg. wydawnictwa
          if product.respond_to?(:publisher_product_categories)
            product.publisher_product_categories.each do |product_category|
              tag(:Subject) do
                tag(:SubjectSchemeIdentifier, Elibri::ONIX::Dict::Release_3_0::SubjectSchemeIdentifier::PROPRIETARY)
                tag(:SubjectSchemeName, product.publisher_name)
                tag(:SubjectCode, product_category.id)
                tag(:SubjectHeadingText, product_category.name)
              end
            end
          end

          if product.respond_to?(:polish_aggregated_categories)
            product.polish_aggregated_categories.each do |category|
              tag(:Subject) do
                tag(:SubjectSchemeIdentifier, Elibri::ONIX::Dict::Release_3_0::SubjectSchemeIdentifier::PROPRIETARY)
                tag(:SubjectSchemeName, "Polish Aggregated Category")
                tag(:SubjectHeadingText, category)
              end
            end
          end

          if product.respond_to?(:keywords) && product.keywords.size > 0
            by_lan = product.keywords.group_by { |k| k.language && k.language.size > 0 ? k.language : @lan }

            tag(:Subject) do
              tag(:SubjectSchemeIdentifier, Elibri::ONIX::Dict::Release_3_0::SubjectSchemeIdentifier::KEYWORDS)
              by_lan.keys.sort.each do |language|
                tag(:SubjectHeadingText, by_lan[language].map(&:keyword).join("; "), language: language)
              end
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier ProductComposition ProductForm TitleDetail
        # @title Autorzy, redaktorzy ...
        # Każdy produkt może mieć wymienionych autorów, może być informacja, że jest to praca zbiorowa, produkt może nie mieć też żadnego autora (np. mapa)
        #
        #
        # Każdy twórca ma przypisaną jedną z wielu ról (&lt;ContributorRole&gt;). W przypadku tłumacza dodawana jest informacja, z jakiego języka
        # nastąpiło tłumaczenie (&lt;FromLanguage&gt;)
        #
        #
        # W przypadku właściwego uzupełnienia danych w eLibri, system potrafi podzielić fragmenty personaliów
        # autora i wyeksportować je w oddzielnych tagach ONIX. Rozróżniane są następujące fragmenty: tytuł naukowy (&lt;TitlesBeforeNames&gt;),
        # imię (&lt;NamesBeforeKey&gt;), prefix nazwiska (von, van - &lt;PrefixToKey&gt;), nazwisko (&lt;KeyNames&gt;),
        # postfix nazwiska (najczęściej określenie zakonu, np. OP - &lt;NamesAfterKey&gt;).
        # Zawsze jest jednak exportowane pełne brzemienie imienia i nazwiska (&lt;PersonName&gt;)
        #
        #
        # Zdarzają się również przypadki, gdzie wyżej podany podział nie jest albo znany, albo możliwy (np. św. Tomasz z Akwinu), wtedy
        # exportowany jest tylko tag &lt;PersonName&gt;
        #
        # Jeśli wydawnictwo uzupełniło biogram autora, to jest on dostępny w tagu &lt;BiographicalNote&gt;
        #
        # @render onix_contributors_example
        #
        # W przypadku pracy zbiorowej rekord wygląda następująco:
        #
        # @render onix_collective_work_example
        #
        # Jeśli produkt nie ma żadnego autora, użyty zostaje tag &lt;NoContributor&gt;
        #
        # @render onix_no_contributors_example
        #
        #
        def export_contributors!(product)
          if product.authorship_kind == "user_given"
            comment 'Gdy wyszczególniono autorów', :kind => :onix_contributors if product.contributors && product.contributors.size > 0
            product.contributors.each_with_index do |contributor, idx|
              options = {}
              unless @skip_sourcename_and_timestamp
                options[:sourcename] = "contributorid:#{contributor.id}" if contributor.respond_to?(:id)
                options[:datestamp] = contributor.updated_at.to_s(:onix) if contributor.respond_to?(:updated_at)
              end
              tag(:Contributor,  options) do
                tag(:SequenceNumber, idx + 1)
                comment_dictionary 'Rola autora', :ContributorRole, :indent => 10, :kind => :onix_contributors
                tag(:ContributorRole, contributor.role_onix_code) #lista 17
                comment 'Tylko w przypadku tłumaczy:', :kind => :onix_contributors
                tag(:FromLanguage, contributor.language_onix_code) if field_exists?(contributor, :language_onix_code)
                tag(:PersonName, contributor.generated_full_name)
                if field_exists?(contributor, :name) && field_exists?(contributor, :last_name)   #muszą być przynajmniej te dwa pola
                  tag(:TitlesBeforeNames, contributor.title) if field_exists?(contributor, :title)
                  tag(:NamesBeforeKey, contributor.name) if field_exists?(contributor, :name)
                  tag(:PrefixToKey, contributor.last_name_prefix) if field_exists?(contributor, :last_name_prefix)
                  tag(:KeyNames, contributor.last_name) if field_exists?(contributor, :last_name)
                  tag(:NamesAfterKey, contributor.last_name_postfix) if field_exists?(contributor, :last_name_postfix)
                end
                if contributor.respond_to?(:biography) && contributor.biography && contributor.biography.text && contributor.biography.text.strip.size > 0
                  tag(:BiographicalNote, contributor.biography.text)
                end
              end
            end
          end

          if product.authorship_kind == "collective"
            comment 'Gdy jest to praca zbiorowa', :kind => :onix_contributors
            tag(:Contributor) do
              comment "Autor - #{Elibri::ONIX::Dict::Release_3_0::ContributorRole::AUTHOR}", :kind => :onix_contributors
              tag(:ContributorRole, Elibri::ONIX::Dict::Release_3_0::ContributorRole::AUTHOR)
              comment "Różne osoby - #{Elibri::ONIX::Dict::Release_3_0::UnnamedPersons::VARIOUS_AUTHORS}", :kind => :onix_contributors
              tag(:UnnamedPersons, Elibri::ONIX::Dict::Release_3_0::UnnamedPersons::VARIOUS_AUTHORS)
            end
          end

          if product.authorship_kind === "no_contributor"
            comment 'Gdy brak autorów', :kind => :onix_contributors
            tag(:NoContributor)
          end
        end

        # @hidden_tags RecordReference NotificationType ProductIdentifier ProductComposition ProductForm
        # @title Tytuły
        # W dokumencie XML mogą pojawić się 3 typy tytułu: pełen tytuł produktu, tytuł w języku oryginału (jeśli jest tłumaczeniem)
        # oraz roboczy tytuł nadany przez wydawcę.
        # @render onix_titles_example
        #
        # Tytuł może być też kaskadowy. Dobrym przykładem jest na przykład Thorgal, komiks, który ma wiele tomów, każdy tom ma swój numer, jak i tytuł.
        # W kategoriach ONIX-a Thorgal jest kolekcją. Od serii odróżnia go to, że jest częścią tytułu. Innym dobrym przykładem jest książka "Gra o Tron",
        # która należy do kolekcji "Pieśń Lodu i Ognia" - ponieważ jest to częścią tytułu.
        # @render onix_title_with_collection_example
        #
        #
        def export_titles!(product)
          if product.title_parts && product.title_parts.size > 0
            tag(:TitleDetail) do
              comment "Pełen tytuł produktu - #{Elibri::ONIX::Dict::Release_3_0::TitleType::DISTINCTIVE_TITLE}", :kind => :onix_titles
              tag(:TitleType, Elibri::ONIX::Dict::Release_3_0::TitleType::DISTINCTIVE_TITLE)
              product.title_parts.each do |title_part|
                tag(:TitleElement) do
                  if title_part.level == Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::PRODUCT
                    comment "Tytuł na poziomie produktu - #{Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::PRODUCT}", :kind => :onix_titles
                  elsif title_part.level == Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::COLLECTION
                    comment "Tytuł na poziomie kolekcji - #{Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::COLLECTION}", :kind => :onix_titles
                  end
                  tag(:TitleElementLevel, title_part.level) #odnosi się do tego produktu tylko
                  tag(:PartNumber, title_part.part) if field_exists?(title_part, :part)
                  tag(:TitleText, title_part.title.strip, language: @lan) if field_exists?(title_part, :title)
                  tag(:Subtitle, title_part.subtitle.strip, language: @lan) if field_exists?(title_part, :subtitle)
                end
              end
            end
          end

          if field_exists?(product, :title_eng)
            tag(:TitleDetail) do
              tag(:TitleType, Elibri::ONIX::Dict::Release_3_0::TitleType::DISTINCTIVE_TITLE)
              tag(:TitleElement) do
                tag(:TitleElementLevel, Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::PRODUCT)
                tag(:TitleText, product.title_eng.strip, language: "eng")
              end
            end
          end


          if field_exists?(product, :original_title)
            tag(:TitleDetail) do
              comment "Tytuł w języku oryginału - #{Elibri::ONIX::Dict::Release_3_0::TitleType::ORIGINAL_TITLE}", :kind => :onix_titles
              tag(:TitleType, Elibri::ONIX::Dict::Release_3_0::TitleType::ORIGINAL_TITLE)
              tag(:TitleElement) do
                comment "Tytuł na poziomie produktu - #{Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::PRODUCT}", :kind => :onix_titles
                tag(:TitleElementLevel, Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::PRODUCT)
                tag(:TitleText, product.original_title.strip)
              end
            end
          end

          if field_exists?(product, :trade_title)
            tag(:TitleDetail) do
              comment "Tytuł handlowy używany przez wydawnictwo - #{Elibri::ONIX::Dict::Release_3_0::TitleType::DISTRIBUTORS_TITLE}", :kind => :onix_titles
              tag(:TitleType, Elibri::ONIX::Dict::Release_3_0::TitleType::DISTRIBUTORS_TITLE) #tytuł produktu
              tag(:TitleElement) do
                comment "Tytuł na poziomie produktu - #{Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::PRODUCT}", :kind => :onix_titles
                tag(:TitleElementLevel, Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::PRODUCT)
                tag(:TitleText, product.trade_title)
              end
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier ProductComposition ProductForm TitleDetail
        # @title Opis wydania
        # System elibri pozwala na dodatkowe opisanie typu wydania w &lt;EditionType&gt;:
        # <ul>
        #   <li>LTE - edycja z powiększoną czcionką</li>
        #   <li>CRI - wydanie krytyczne (z komentarzem)</li>
        #   <li>BLL - wydanie dwujęzyczne</li>
        #   <li>FAC - reprint</li>
        # </ul>
        # Dodatkowo można określić numer wydania w &lt;EditionStatement&gt;
        def export_edition!(product)
          if field_exists?(product, :edition_type_onix_code)
            comment 'Typ wydania', :kind => :onix_edition
            tag(:EditionType, product.edition_type_onix_code)
          end
          if field_exists?(product, :edition_statement)
            comment 'Opis wydania', :kind => :onix_edition
            tag(:EditionStatement, product.edition_statement)
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier ProductComposition ProductForm TitleDetail
        # @title Języki
        # Języki, w których dostępny jest produkt.
        def export_languages!(product)
          if product.respond_to?(:languages)
            comment_dictionary 'Rola języka', :LanguageRole, :indent => 10, :kind => :onix_languages if product.languages.size > 0
            product.languages.each do |language|
              tag(:Language) do
                tag(:LanguageRole, language.role_onix_code)     #lista 22
                tag(:LanguageCode, language.language_onix_code) #lista 74
              end
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier DescriptiveDetail
        # @title Teksty
        # Wydawca może wprowadzić do eLibri różne informacje tekstowe - opis produktu, spis treści, recenzję (jeśli ma prawa ją udostępnić), jak i fragment książki.
        # Biogramy autorów są udostępniane wraz z informacjami o
        # = link_to "autorach", doc_api_path("onix_contributors")
        def export_texts!(product)
          comment_dictionary 'Typy tekstów', :OtherTextType, :indent => 10, :kind => :onix_texts if product.other_texts && product.other_texts.size > 0
          product.other_texts.each do |other_text|
            #jeśli jest pusty tekst, nie nadaje się do umieszczania w ONIX albo tekst dotyczy autora (type_onix_code.blank?) -> nie exportuj
            next if other_text.text.nil? || other_text.text.strip.size == 0 || other_text.type_onix_code.nil? || other_text.type_onix_code.strip.size == 0 || !other_text.exportable?

            options = {}
            unless @skip_sourcename_and_timestamp
              options[:sourcename] = "textid:#{other_text.id}" if other_text.respond_to?(:id)
              options[:datestamp] = other_text.updated_at.to_s(:onix) if other_text.respond_to?(:updated_at)
            end
            tag(:TextContent, options) do
              tag(:TextType, other_text.type_onix_code) #lista 153
              comment "Zawsze #{Elibri::ONIX::Dict::Release_3_0::ContentAudience::UNRESTRICTED} - Unrestricted", :kind => :onix_texts
              tag(:ContentAudience, Elibri::ONIX::Dict::Release_3_0::ContentAudience::UNRESTRICTED)

              if other_text.respond_to?(:is_a_review?) && other_text.respond_to?(:resource_link) &&
                 other_text.is_a_review? && other_text.resource_link && other_text.resource_link.size > 0
                text_source = {:sourcename => other_text.resource_link}
              else
                text_source = {}
              end

              tag(:Text, text_source.merge(language: @lan)) do |builder|
                builder.cdata!(other_text.text)
              end

              if field_exists?(other_text, :text_eng)
                tag(:Text, language: "eng") do |builder|
                  builder.cdata!(other_text.text_eng)
                end
              end

              tag(:TextAuthor, other_text.text_author) if field_exists?(other_text, :text_author)
              tag(:SourceTitle, other_text.source_title) if field_exists?(other_text, :source_title)
            end
          end
          if field_exists?(product, :open_access_statement)
            tag(:TextContent) do
              tag(:TextType, Elibri::ONIX::Dict::Release_3_0::OtherTextType::OPEN_ACCESS_STATEMENT)
              tag(:ContentAudience, Elibri::ONIX::Dict::Release_3_0::ContentAudience::UNRESTRICTED)
              tag(:Text, product.open_access_statement)
            end
          end

          if field_exists?(product, :box_content)
            tag(:TextContent) do
              tag(:TextType, Elibri::ONIX::Dict::Release_3_0::OtherTextType::LIST_OF_CONTENTS)
              tag(:ContentAudience, Elibri::ONIX::Dict::Release_3_0::ContentAudience::UNRESTRICTED)
              tag(:Text, product.box_content)
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier DescriptiveDetail
        # @title Załączniki
        # Wydawca może załączyć do każdego produktu dowolną liczbę plików - a przynajmniej jeden, okładkę. Proszę za każdym razem
        # tworzyć kopię pliku na swoim serwerze, hotlinking jest niedozwolony.
        def export_supporting_resources!(product)
          product.attachments.each do |attachment|
            if attachment.onix_resource_mode #jeśli klient coś dzikiego wgrał, to ignoruj to
              options = {}
              unless @skip_sourcename_and_timestamp
                options[:sourcename] = "resourceid:#{attachment.id}" if attachment.respond_to?(:id)
                options[:datestamp] = attachment.updated_at.utc.to_s(:onix) if attachment.respond_to?(:updated_at)
              end
              tag(:SupportingResource, options) do
                comment_dictionary 'Typ załącznika', :ResourceContentType, :indent => 12, :kind => :onix_supporting_resources
                tag(:ResourceContentType, attachment.attachment_type_code) #lista 158
                comment 'Zawsze 00 - Unrestricted', :kind => :onix_supporting_resources
                tag(:ContentAudience, Elibri::ONIX::Dict::Release_3_0::ContentAudience::UNRESTRICTED)
                comment_dictionary 'Rodzaj załącznika', :ResourceMode, :indent => 12, :kind => :onix_supporting_resources
                tag(:ResourceMode, attachment.onix_resource_mode) #lista 159
                tag(:ResourceVersion) do
                  comment 'Zawsze 02 - Downloadable file', :kind => :onix_supporting_resources
                  tag(:ResourceForm, Elibri::ONIX::Dict::Release_3_0::ResourceForm::DOWNLOADABLE_FILE)

                  comment 'md5 pliku'
                  tag(:ResourceVersionFeature) do
                    tag(:ResourceVersionFeatureType, Elibri::ONIX::Dict::Release_3_0::ResourceVersionFeatureType::MD5_HASH_VALUE) #lista 162
                    tag(:FeatureValue, attachment.file_md5)
                  end

                  comment 'wielkość pliku w bajtach'
                  tag(:ResourceVersionFeature) do
                    tag(:ResourceVersionFeatureType, Elibri::ONIX::Dict::Release_3_0::ResourceVersionFeatureType::SIZE_IN_BYTES)  #lista 162
                    tag(:FeatureValue, attachment.file_size)
                  end

                  tag(:ResourceLink, attachment.url_for_onix)
                  if attachment.respond_to?(:updated_at)
                    tag(:ContentDate) do
                      tag(:ContentDateRole, Elibri::ONIX::Dict::Release_3_0::ContentDateRole::LAST_UPDATED)
                      tag(:Date, attachment.updated_at.utc.strftime("%Y%m%dT%H%MZ"), dateformat: Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMMDDTHHMM)
                    end
                  end
                end
              end
            end
          end

          if product.respond_to?(:preview) && product.preview
            options = {}
            tag(:SupportingResource) do
              tag(:ResourceContentType, Elibri::ONIX::Dict::Release_3_0::ResourceContentType::WIDGET) #lista 158
              tag(:ContentAudience, Elibri::ONIX::Dict::Release_3_0::ContentAudience::UNRESTRICTED)
              tag(:ResourceMode, Elibri::ONIX::Dict::Release_3_0::ResourceMode::TEXT) #lista 159
              tag(:ResourceVersion) do
                tag(:ResourceForm, Elibri::ONIX::Dict::Release_3_0::ResourceForm::EMBEDDABLE_APPLICATION)
                tag(:ResourceLink, product.preview.url_for_onix)
                tag(:ContentDate) do
                  tag(:ContentDateRole, Elibri::ONIX::Dict::Release_3_0::ContentDateRole::LAST_UPDATED)
                  tag(:Date, product.preview.updated_at.utc.strftime("%Y%m%dT%H%MZ"), dateformat: Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMMDDTHHMM)
                end
              end
            end
          end

          if product.respond_to?(:digital?) && product.digital? && product.respond_to?(:excerpts) && product.excerpts.present?
            options = {}
            tag(:SupportingResource) do
              tag(:ResourceContentType, Elibri::ONIX::Dict::Release_3_0::ResourceContentType::SAMPLE_CONTENT)
              tag(:ContentAudience, Elibri::ONIX::Dict::Release_3_0::ContentAudience::UNRESTRICTED)
              tag(:ResourceMode, product.excerpt_onix_resource_mode) #lista 159
              product.excerpts.each do |excerpt|
                tag(:ResourceVersion) do
                  tag(:ResourceForm, Elibri::ONIX::Dict::Release_3_0::ResourceForm::DOWNLOADABLE_FILE)

                  comment 'format pliku'
                  tag(:ResourceVersionFeature) do
                    tag(:ResourceVersionFeatureType, Elibri::ONIX::Dict::Release_3_0::ResourceVersionFeatureType::FILE_FORMAT)    #lista 162
                    tag(:FeatureValue, excerpt.excerpt_onix_type_name)
                  end

                  comment 'md5 pliku'
                  tag(:ResourceVersionFeature) do
                    tag(:ResourceVersionFeatureType, Elibri::ONIX::Dict::Release_3_0::ResourceVersionFeatureType::MD5_HASH_VALUE) #lista 162
                    tag(:FeatureValue, excerpt.file_md5)
                  end

                  comment 'wielkość pliku w bajtach'
                  tag(:ResourceVersionFeature) do
                    tag(:ResourceVersionFeatureType, Elibri::ONIX::Dict::Release_3_0::ResourceVersionFeatureType::SIZE_IN_BYTES)  #lista 162
                    tag(:FeatureValue, excerpt.file_size)
                  end

                  tag(:ResourceLink, excerpt.public_url)
                  tag(:ContentDate) do
                    tag(:ContentDateRole, Elibri::ONIX::Dict::Release_3_0::ContentDateRole::LAST_UPDATED)
                      tag(:Date, excerpt.stored_updated_at.utc.strftime("%Y%m%dT%H%MZ"), dateformat: Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMMDDTHHMM)
                  end
                end
              end
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier ProductComposition ProductForm
        # @title Serie wydawnicze
        # Serie wydawnicze są opisywane w podobny sposób co tytuł, zawarte są jednak w tagu <strong>&lt;Collection&gt;</strong>
        # Struktura jest dosyć zawiła, ale wszystkie wartości są sztywne, więc nie powinno być problemu z odczytaniem informacji.
        # Oprócz nazwy serii może zostać również podany numer wewnątrz serii, jeśli seria jest numerowana.
        # Książka może należeć do kilku serii, wtedy tag <strong>&lt;Collection&gt;</strong> występuje kilkukrotnie.
        def export_series_memberships!(product)
          if product.respond_to?(:series_membership_kind) && (product.series_membership_kind == "user_given" || product.collection_with_issn)
            (product.series_memberships + [product.collection_with_issn]).compact.each_with_index do |series_membership, idx|
              tag(:Collection) do
                comment "Używamy tylko #{Elibri::ONIX::Dict::Release_3_0::CollectionType::PUBLISHER_COLLECTION} - seria wydawnictwa", :kind => :onix_series_memberships
                tag(:CollectionType, Elibri::ONIX::Dict::Release_3_0::CollectionType::PUBLISHER_COLLECTION) #lista 148

                if field_exists?(series_membership, :issn)
                  comment "W przypadku prasy serializowany jest numer ISSN"
                  tag(:CollectionIdentifier) do
                    tag(:CollectionIDType, "02") #issn - lista 13
                    tag(:IDValue, series_membership.issn)
                  end
                end
                comment "Teraz następuje podobna struktura, jak w przypadku tytułu", :kind => :onix_series_memberships
                tag(:TitleDetail) do
                  comment "Używamy tylko #{Elibri::ONIX::Dict::Release_3_0::TitleType::DISTINCTIVE_TITLE}", :kind => :onix_series_memberships
                  tag(:TitleType, Elibri::ONIX::Dict::Release_3_0::TitleType::DISTINCTIVE_TITLE)
                  tag(:TitleElement) do
                    comment "Używamy tylko #{Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::COLLECTION}", :kind => :onix_series_memberships
                    tag(:TitleElementLevel, Elibri::ONIX::Dict::Release_3_0::TitleElementLevel::COLLECTION)
                    tag(:PartNumber, series_membership.number_within_series) if field_exists?(series_membership, :number_within_series)
                    tag(:TitleText, series_membership.series_name)
                  end
                end
              end
            end
          end
        end


        # @hidden_tags RecordReference NotificationType ProductIdentifier DescriptiveDetail
        # @title Powiązane produkty
        def export_related_products!(product)
          tag(:RelatedMaterial) do

            comment_dictionary "Typy relacji", :ProductRelationType, :indent => 10, :kind => :onix_related_products
            product.facsimiles_for_onix.each do |facsimile|
              tag(:RelatedProduct) do
                tag(:ProductRelationCode, Elibri::ONIX::Dict::Release_3_0::ProductRelationType::FACSIMILES)
                tag(:ProductIdentifier) do
                  comment "Zawsze #{Elibri::ONIX::Dict::Release_3_0::ProductIDType::PROPRIETARY} - wewnętrzny kod elibri (record reference)",
                          :kind => :onix_related_products
                  tag(:ProductIDType, Elibri::ONIX::Dict::Release_3_0::ProductIDType::PROPRIETARY)
                  tag(:IDTypeName, "elibri")
                  tag(:IDValue, facsimile.record_reference)
                end
              end
            end
          end
        end


        # @hidden_tags RecordReference NotificationType DescriptiveDetail Supplier ProductAvailability Price
        # @title Stany magazynowe
        # Tag <strong>&lt;Stock&gt;</strong> może zawierać konkretną ilość produktu w <strong>&ltOnHand&gt;</strong>,
        # lub słownie określoną ilość w <strong>&lt;StockQuantityCoded&gt;</strong>.<br/><br/>
        # Dokument XML zawierający dane o stanach magazynowych produktu najczęściej zawiera także rozszerzoną listę
        # identyfikatorów produktu. Poza podstawowym <strong>&lt;ProductIdentifier&gt;</strong>, znajdują się także identyfikatory
        # poszczególnych dostawców. Tag <strong>&lt;IDTypeName&gt;</strong> zawiera nazwę dostawcy.
        def export_supply_details!(product)
          return if product.respond_to?(:skip_ProductSupply) && product.skip_ProductSupply || !product.respond_to?(:product_availabilities)
          unless product.product_availabilities.empty?
            tag(:ProductSupply) do
              product.product_availabilities.each do |pa|
                tag(:SupplyDetail) do
                  tag(:Supplier) do
                    comment_dictionary "Rola dostawcy", :SupplierRole, :indent => 12
                    tag(:SupplierRole, pa.supplier_role_onix_code) #lista 93
                    if pa.supplier.vatid.present?
                      tag(:SupplierIdentifier) do
                        comment "Zawsze 02 - Proprietary. Identyfikujemy dostawcę po NIP"
                        tag(:SupplierIDType, Elibri::ONIX::Dict::Release_3_0::SupplierIDType::VAT_IDENTITY_NUMBER) #lista 92, NIP
                        tag(:IDValue, pa.supplier.vatid)
                      end
                    end
                    tag(:SupplierName, pa.supplier.name)
                    tag(:TelephoneNumber, pa.supplier.phone) if field_exists?(pa.supplier, :phone)
                    tag(:EmailAddress, pa.supplier.email) if field_exists?(pa.supplier, :email)
                    if field_exists?(pa, :website)
                      Array(pa.website).each do |website|
                        tag(:Website) do
                          tag(:WebsiteRole, website.role)
                          tag(:WebsiteDescription, website.description)
                          tag(:WebsiteLink, website.url)
                        end
                      end
                    end
                  end
                  if field_exists?(product, :additional_info)
                    comment 'Dodatkowa klasyfikacja sprzedażowa od wydawcy - np. promocja, albo wyprzedaż'
                    tag(:SupplierOwnCoding) do
                      tag(:SupplierCodeType, Elibri::ONIX::Dict::Release_3_0::SupplierOwnCodeType::SUPPLIERS_SALES_CLASSIFICATION)
                      tag(:SupplierCodeValue, product.additional_info)
                    end
                  end

                  comment_dictionary "Typ dostępności", :ProductAvailabilityType, :indent => 10
                  tag(:ProductAvailability, pa.product_availability_onix_code) #lista 65
                  if field_exists?(pa, :stock_info)
                    tag(:Stock) do
                      tag(:OnHand, pa.stock_info.on_hand)
                      tag(:Proximity, pa.stock_info.proximity)
                    end
                  end
                  if field_exists?(product, :pack_quantity) && product.pack_quantity.to_i > 0
                    comment 'Ile produktów dostawca umieszcza w paczce'
                    tag(:PackQuantity, product.pack_quantity)
                  end

                  if product.respond_to?(:unpriced_item?) && product.unpriced_item?
                    tag(:UnpricedItemType, Elibri::ONIX::Dict::Release_3_0::UnpricedItemType::FREE_OF_CHARGE)
                  end

                  if pa.respond_to?(:price_infos)
                    pa.price_infos.each do |price_info|
                      tag(:Price) do
                        comment_dictionary "Typ ceny", :PriceTypeCode, :indent => 12
                        tag(:PriceType, Elibri::ONIX::Dict::Release_3_0::PriceTypeCode::RRP_WITH_TAX) #lista 58
                        tag(:MinimumOrderQuantity, price_info.minimum_order_quantity) if price_info.minimum_order_quantity
                        tag(:PriceAmount, price_info.amount)
                        tag(:Tax) do
                          comment 'VAT'
                          tag(:TaxType, Elibri::ONIX::Dict::Release_3_0::TaxType::VAT) #lista 171, VAT
                          tag(:TaxRatePercent, price_info.vat)
                        end
                        tag(:CurrencyCode, price_info.currency_code)
                        if field_exists?(price_info, :price_date)
                          tag(:PriceDate) do
                            tag(:PriceDateRole, price_info.price_date.price_date_role)
                            tag(:Date, price_info.price_date.date.strftime("%Y%m%d"))
                          end
                        end
                        if field_exists?(product, :price_printed_on_product_onix_code)
                          comment_dictionary "Cena na okładce?", :PricePrintedOnProduct, :indent => 12
                          tag(:PrintedOnProduct, product.price_printed_on_product_onix_code)  #lista 174
                          if product.price_printed_on_product_onix_code == Elibri::ONIX::Dict::Release_3_0::PricePrintedOnProduct::YES
                            comment 'Zawsze 00 - Unknown / unspecified'
                            tag(:PositionOnProduct, Elibri::ONIX::Dict::Release_3_0::PricePositionOnProduct::UNKNOW) #lista 142 - Position unknown or unspecified
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end

        def export_masters_info!(product)
          if product.respond_to?(:digital_or_pod?) && product.digital_or_pod? && product.respond_to?(:masters) && product.masters.size > 0
            tag("ProductionDetail") do
              tag("ProductionManifest") do
                tag("BodyManifest") do
                  product.masters.each_with_index do |master, idx|
                    tag("BodyResource") do
                      tag("SequenceNumber", idx + 1)
                      tag("ResourceIdentifier") do
                        tag("ResourceIDType", Elibri::ONIX::Dict::Release_3_0::ResourceIDType::PROPRIETARY)
                        tag("IDTypeName", "elibri internal numerical ID")
                        tag("IDValue", master.id)
                      end
                      tag("ResourceFileFeature") do
                        tag("ResourceFileFeatureType", Elibri::ONIX::Dict::Release_3_0::ResourceFileFeatureType::EXACT_FILE_SIZE)
                        tag("ResourceFileFeatureValue", master.file_size)
                      end

                      tag("ResourceFileFeature") do
                        tag("ResourceFileFeatureType", Elibri::ONIX::Dict::Release_3_0::ResourceFileFeatureType::MD5)
                        tag("ResourceFileFeatureValue", master.file_md5)
                      end
                      tag("ResourceFileLink", master.stored_file_name)
                      tag("ResourceFileDate") do
                        tag("ResourceFileDateRole", Elibri::ONIX::Dict::Release_3_0::ContentDateRole::LAST_UPDATED)
                        tag("Date", master.stored_updated_at.utc.strftime("%Y%m%dT%H%MZ"), dateformat: Elibri::ONIX::Dict::Release_3_0::DateFormat::YYYYMMDDTHHMM)
                      end
                    end
                  end
                end
              end
            end
          end
        end

        # @title Rozszerzenia eLibri dla ONIX
        # @hidden_tags RecordReference NotificationType ProductIdentifier DescriptiveDetail
        # Standard ONIX nie przewiduje w chwili obecnej atrybutów produktów niezbędnych z punktu widzenia polskiego rynku wydawniczego.
        # Są to atrybuty takie jak np. Vat czy PKWiU. eLibri rozszerza więc ONIX o kilka użytecznych tagów, wprowadzając nową przestrzeń nazw
        # w generowanych XML'ach.
        def export_elibri_extensions!(product)
          if @elibri_onix_dialect >= '3.0.1'

            if field_exists?(product, :cover_type)
              begin
                comment_dictionary "Format okładki", Product::CoverType.all.map(&:name), :indent => 10
              rescue NameError
              end
              tag("elibri:CoverType", product.cover_type.name)
            end

            comment 'Cena na okładce'
            tag("elibri:CoverPrice", product.price_amount) if field_exists?(product, :price_amount)
            comment 'Vat w procentach'
            tag("elibri:Vat", product.vat) if field_exists?(product, :vat)
            tag("elibri:PKWiU", product.pkwiu) if field_exists?(product, :pkwiu)
            tag("elibri:PDWExclusiveness", product.pdw_exclusiveness) if field_exists?(product, :pdw_exclusiveness)
            tag("elibri:AdditionalInfo", product.additional_info) if field_exists?(product, :additional_info)
            tag("elibri:preview_exists", product.preview_exists?.to_s) if product.respond_to?(:preview_exists?)
            if product.respond_to?(:digital?) && product.digital?
              if product.epub_sale_not_restricted? || product.epub_sale_restricted_to_for_onix.nil?
                tag("elibri:SaleNotRestricted")
              else
                tag("elibri:SaleRestrictedTo", product.epub_sale_restricted_to_for_onix.strftime("%Y%m%d"))
              end
            end
            if product.respond_to?(:isbn) && product.isbn
              tag("elibri:HyphenatedISBN", product.isbn.human_value)
            end

            if product.respond_to?(:digital_or_pod?) && product.digital_or_pod?
              if product.excerpts.size > 0
                 tag("elibri:excerpts") do
                   product.excerpts.each do |excerpt|
                     tag("elibri:excerpt", excerpt.public_url, :md5 => excerpt.file_md5, :file_size => excerpt.file_size,
                                           :file_type => excerpt.file_type, :updated_at => excerpt.stored_updated_at.to_datetime.xmlschema, :id => excerpt.id)
                   end
                 end
              end
              if product.masters.size > 0
                tag("elibri:masters") do
                  product.masters.each do |sf|
                    tag("elibri:master", :id => sf.id, :md5 => sf.file_md5, :file_size => sf.file_size,
                                         :file_type => sf.file_type, :updated_at => sf.stored_updated_at.to_datetime.xmlschema)
                  end
                end
              end
            end
          end
        end

    end
  end
end
