require "json"
require "base64"
require "./adapter"
require "./factory"

module CrystalUI::Plugins
  # Clipboard plugin.
  #
  # Exposes a host-side API to the frontend:
  #   - clipboard.read_text() -> String?
  #   - clipboard.read_image() -> String? (base64 data URI)
  #   - clipboard.read_files() -> Array(String)
  #   - clipboard.has_text() -> Bool
  #   - clipboard.has_image() -> Bool
  #   - clipboard.has_files() -> Bool
  #   - clipboard.write_text({ text }) -> Bool
  #   - clipboard.write_image({ data, mime }) -> Bool
  #
  # Platform adapters live in `src/crystal_ui/plugins/clipboard/` and are
  # selected at compile time by `ClipboardAdapterFactory`.
  class Clipboard < CrystalUI::Plugin
    @adapter : ClipboardAdapter

    def initialize
      @adapter = ClipboardAdapterFactory.create
    end

    def name : String
      "clipboard"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "clipboard.read_text" => CrystalUI::CommandManifest.new(
          name: "clipboard.read_text",
          returns: "String?"
        ),
        "clipboard.read_image" => CrystalUI::CommandManifest.new(
          name: "clipboard.read_image",
          returns: "String?"
        ),
        "clipboard.read_files" => CrystalUI::CommandManifest.new(
          name: "clipboard.read_files",
          returns: "Array(String)"
        ),
        "clipboard.has_text" => CrystalUI::CommandManifest.new(
          name: "clipboard.has_text",
          returns: "Bool"
        ),
        "clipboard.has_image" => CrystalUI::CommandManifest.new(
          name: "clipboard.has_image",
          returns: "Bool"
        ),
        "clipboard.has_files" => CrystalUI::CommandManifest.new(
          name: "clipboard.has_files",
          returns: "Bool"
        ),
        "clipboard.write_text" => CrystalUI::CommandManifest.new(
          name: "clipboard.write_text",
          args: [
            CrystalUI::ArgumentManifest.new(name: "text", type: "String"),
          ],
          returns: "Bool"
        ),
        "clipboard.write_image" => CrystalUI::CommandManifest.new(
          name: "clipboard.write_image",
          args: [
            CrystalUI::ArgumentManifest.new(name: "data", type: "String"),
            CrystalUI::ArgumentManifest.new(name: "mime", type: "String"),
          ],
          returns: "Bool"
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("clipboard.read_text") do |_request|
        text = @adapter.read_text

        CrystalUI::CommandResult.new(
          success: true,
          data: text.nil? ? JSON.parse("null") : JSON.parse(text.to_json)
        )
      end

      registry.register("clipboard.read_image") do |_request|
        uri = image_data_uri

        CrystalUI::CommandResult.new(
          success: true,
          data: uri.nil? ? JSON.parse("null") : JSON.parse(uri.to_json)
        )
      end

      registry.register("clipboard.read_files") do |_request|
        files = @adapter.read_files

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(files.to_json)
        )
      end

      registry.register("clipboard.has_text") do |_request|
        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(@adapter.has_text?.to_json)
        )
      end

      registry.register("clipboard.has_image") do |_request|
        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(@adapter.has_image?.to_json)
        )
      end

      registry.register("clipboard.has_files") do |_request|
        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(@adapter.has_files?.to_json)
        )
      end

      registry.register("clipboard.write_text") do |request|
        text = request.args["text"].as_s
        ok = @adapter.write_text(text)

        CrystalUI::CommandResult.new(
          success: ok,
          data: JSON.parse(ok.to_json)
        )
      end

      registry.register("clipboard.write_image") do |request|
        data = request.args["data"].as_s
        mime = request.args["mime"].as_s
        ok = @adapter.write_image(data, mime)

        CrystalUI::CommandResult.new(
          success: ok,
          data: JSON.parse(ok.to_json)
        )
      end
    end

    private def image_data_uri : String?
      image = @adapter.read_image
      return nil unless image

      base64 = Base64.strict_encode(image[:data])
      "data:#{image[:mime]};base64,#{base64}"
    end
  end
end
