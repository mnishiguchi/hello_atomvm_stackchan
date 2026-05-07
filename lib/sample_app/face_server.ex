# SPDX-FileCopyrightText: 2026 piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp.FaceServer do
  @moduledoc false

  use GenServer

  alias SampleApp.Face

  @default_expression :neutral
  @expression_order [:neutral, :happy, :angry, :sad, :doubt, :sleepy]

  @touch_ms 10
  @frame_ms 500
  @min_render_ms 16
  @expression_interval_ms 10_000

  @touch_center_x 160.0
  @touch_center_y 120.0
  @touch_mouth_open 1.0

  @sample_open_options [
    board_preset: :m5stack_cores3,
    panel_driver: :ili9342c,
    width: 320,
    height: 240,
    offset_rotation: 3,
    readable: false,
    invert: true,
    rgb_order: false,
    dlen_16bit: false,
    lcd_spi_host: :spi2_host,
    spi_sclk_gpio: 36,
    spi_mosi_gpio: 37,
    spi_miso_gpio: -1,
    lcd_cs_gpio: 3,
    lcd_dc_gpio: 35,
    lcd_rst_gpio: -1,
    touch_driver: :ft6336u,
    touch_i2c_port: 1,
    touch_i2c_addr: 0x38,
    touch_sda_gpio: 12,
    touch_scl_gpio: 11,
    touch_bus_shared: false
  ]

  def start_link(open_options \\ []) do
    GenServer.start_link(__MODULE__, open_options, name: __MODULE__)
  end

  def set_expression(expression) do
    GenServer.call(__MODULE__, {:set_expression, expression})
  end

  def set_gaze(horizontal, vertical) do
    GenServer.call(__MODULE__, {:set_gaze, horizontal, vertical})
  end

  def set_mouth_open(ratio) do
    GenServer.call(__MODULE__, {:set_mouth_open, ratio})
  end

  def get_face_state do
    GenServer.call(__MODULE__, :get_face_state)
  end

  @impl GenServer
  def init(open_options) do
    effective_open_options = @sample_open_options ++ open_options
    log_info("about to open AtomLGFX open_options=#{inspect(effective_open_options)}")

    case AtomLGFX.open(effective_open_options) do
      {:ok, port} ->
        log_info("AtomLGFX opened open_options=#{inspect(effective_open_options)}")

        case initialize_face(port) do
          {:ok, face} ->
            log_info("Stack-chan started")
            schedule_touch()
            schedule_frame(0)

            {:ok,
             %{
               port: port,
               face: face,
               expression_index: expression_index(@default_expression),
               last_expression_change_ms: monotonic_ms(),
               remote_mouth_open: nil,
               touch_active: false,
               render_requested: false,
               last_render_ms: 0
             }}

          {:error, reason} ->
            safe_close_port(port)
            {:stop, reason}
        end

      {:error, reason} ->
        log_failure("AtomLGFX open failed", reason)
        {:stop, {:atomlgfx_open_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:set_expression, expression}, _from, state) do
    if expression in @expression_order do
      now_ms = monotonic_ms()
      updated_face = Face.set_expression(state.face, expression)

      next_state =
        %{
          state
          | face: updated_face,
            expression_index: expression_index(expression),
            last_expression_change_ms: now_ms
        }
        |> request_render(now_ms)

      {:reply, :ok, next_state}
    else
      {:reply, {:error, {:unsupported_expression, expression}}, state}
    end
  end

  def handle_call({:set_gaze, horizontal, vertical}, _from, state)
      when is_number(horizontal) and is_number(vertical) do
    now_ms = monotonic_ms()

    next_state =
      %{state | face: Face.set_gaze(state.face, horizontal, vertical)}
      |> request_render(now_ms)

    {:reply, :ok, next_state}
  end

  def handle_call({:set_gaze, horizontal, vertical}, _from, state) do
    {:reply, {:error, {:invalid_gaze, {horizontal, vertical}}}, state}
  end

  def handle_call({:set_mouth_open, ratio}, _from, state) when is_number(ratio) do
    now_ms = monotonic_ms()
    normalized_ratio = clamp(ratio * 1.0, 0.0, 1.0)

    next_state =
      %{
        state
        | face: Face.set_mouth_open(state.face, normalized_ratio),
          remote_mouth_open: normalized_ratio
      }
      |> request_render(now_ms)

    {:reply, :ok, next_state}
  end

  def handle_call({:set_mouth_open, ratio}, _from, state) do
    {:reply, {:error, {:invalid_mouth_open, ratio}}, state}
  end

  def handle_call(:get_face_state, _from, state) do
    face = state.face

    {:reply,
     %{
       expression: face.expr,
       gaze_h: face.gaze_h,
       gaze_v: face.gaze_v,
       mouth_open: face.mouth_open,
       remote_mouth_open: state.remote_mouth_open,
       touch_active: state.touch_active
     }, state}
  end

  @impl GenServer
  def handle_info(:touch_tick, state) do
    {next_state, mouth_changed} = handle_touch(state)
    schedule_touch()

    if mouth_changed do
      draw_mouth_or_stop(next_state)
    else
      {:noreply, next_state}
    end
  end

  def handle_info(:frame_tick, %{touch_active: true} = state) do
    schedule_frame(@frame_ms)
    {:noreply, state}
  end

  def handle_info(:frame_tick, state) do
    schedule_frame(@frame_ms)
    render_or_stop(state, monotonic_ms())
  end

  def handle_info(:render_now, state) do
    render_or_stop(state, monotonic_ms())
  end

  @impl GenServer
  def terminate(_reason, state) do
    safe_close_port(state.port)
    :ok
  end

  defp initialize_face(port) do
    with :ok <- step("ping", AtomLGFX.ping(port)),
         :ok <- step("init", AtomLGFX.init(port)),
         :ok <- step("set_rotation", AtomLGFX.set_rotation(port, 1)),
         :ok <- step("set_swap_bytes_lcd", AtomLGFX.set_swap_bytes(port, true, 0)) do
      face0 =
        Face.new(display_width: 320, display_height: 240)
        |> Face.set_expression(@default_expression)

      case Face.init(face0, port) do
        {:ok, face} ->
          {:ok, face}

        {:error, reason} = err ->
          log_failure("face_init failed", reason)
          err
      end
    end
  end

  defp handle_touch(state) do
    case AtomLGFX.get_touch(state.port) do
      {:ok, {touch_x, touch_y, _size}} ->
        gaze_h = clamp((touch_x - @touch_center_x) / @touch_center_x, -1.0, 1.0)
        gaze_v = clamp((touch_y - @touch_center_y) / @touch_center_y, -1.0, 1.0)

        updated_face =
          state.face
          |> Face.set_gaze(gaze_h, gaze_v)
          |> Face.set_mouth_open(@touch_mouth_open)

        {%{state | face: updated_face, touch_active: true}, not state.touch_active}

      {:ok, :none} ->
        updated_face = Face.set_mouth_open(state.face, effective_mouth_open(state))
        {%{state | face: updated_face, touch_active: false}, state.touch_active}

      {:error, reason} ->
        log_failure("get_touch failed", reason)
        {state, false}
    end
  end

  defp render_or_stop(state, now_ms) do
    if now_ms - state.last_render_ms < @min_render_ms do
      {:noreply, %{state | render_requested: false}}
    else
      next_state =
        state
        |> maybe_rotate_expression(now_ms)
        |> update_face(now_ms)

      case Face.draw(next_state.face, next_state.port) do
        :ok ->
          {:noreply,
           %{
             next_state
             | render_requested: false,
               last_render_ms: now_ms
           }}

        {:error, reason} ->
          log_failure("face_draw failed", reason)
          {:stop, {:face_draw_failed, reason}, next_state}
      end
    end
  end

  defp draw_mouth_or_stop(state) do
    case Face.draw_mouth_overlay(state.face, state.port) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        log_failure("mouth_overlay_draw failed", reason)
        {:stop, {:mouth_overlay_draw_failed, reason}, state}
    end
  end

  defp request_render(state, now_ms) do
    cond do
      state.render_requested ->
        state

      now_ms - state.last_render_ms < @min_render_ms ->
        state

      true ->
        send(self(), :render_now)
        %{state | render_requested: true}
    end
  end

  defp effective_mouth_open(%{remote_mouth_open: nil}), do: 0.0
  defp effective_mouth_open(%{remote_mouth_open: remote_mouth_open}), do: remote_mouth_open

  defp maybe_rotate_expression(state, now_ms) do
    if now_ms - state.last_expression_change_ms > @expression_interval_ms do
      next_index = rem(state.expression_index + 1, length(@expression_order))
      next_expression = Enum.at(@expression_order, next_index)

      log_info("Expression: #{expression_name(next_expression)}")

      %{
        state
        | expression_index: next_index,
          last_expression_change_ms: now_ms,
          face: Face.set_expression(state.face, next_expression)
      }
    else
      state
    end
  end

  defp update_face(state, now_ms) do
    %{state | face: Face.update(state.face, now_ms)}
  end

  defp schedule_touch do
    Process.send_after(self(), :touch_tick, @touch_ms)
  end

  defp schedule_frame(delay_ms) do
    Process.send_after(self(), :frame_tick, delay_ms)
  end

  defp expression_index(:neutral), do: 0
  defp expression_index(:happy), do: 1
  defp expression_index(:angry), do: 2
  defp expression_index(:sad), do: 3
  defp expression_index(:doubt), do: 4
  defp expression_index(:sleepy), do: 5

  defp monotonic_ms do
    :erlang.monotonic_time(:millisecond)
  end

  defp clamp(value, min_value, _max_value) when value < min_value, do: min_value
  defp clamp(value, _min_value, max_value) when value > max_value, do: max_value
  defp clamp(value, _min_value, _max_value), do: value

  defp expression_name(:neutral), do: "Neutral"
  defp expression_name(:happy), do: "Happy"
  defp expression_name(:angry), do: "Angry"
  defp expression_name(:sad), do: "Sad"
  defp expression_name(:doubt), do: "Doubt"
  defp expression_name(:sleepy), do: "Sleepy"

  defp safe_close_port(port) do
    case AtomLGFX.close(port) do
      :ok ->
        log_info("AtomLGFX closed")
        :ok

      {:error, reason} ->
        log_failure("AtomLGFX close failed", reason)
        :ok
    end
  end

  defp step(label, :ok) do
    log_info("#{label} ok")
    :ok
  end

  defp step(_label, {:error, reason} = err) do
    log_failure("AtomLGFX step failed", reason)
    err
  end

  defp log_info(message) when is_binary(message) do
    IO.puts(message)
  end

  defp log_failure(prefix, reason) when is_binary(prefix) do
    IO.puts("#{prefix}: #{AtomLGFX.format_error(reason)}")
  end
end
