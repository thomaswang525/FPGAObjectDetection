//---------------------------------------------------------------------------------
//Controlador de omunicación entre dispositivos I2C.
//---------------------------------------------------------------------------------
module I2C_CCD_Config (	
	iCLK, 			  //Reloj de entrada
	iRST_N,			  //Reset
	iZOOM_MODE_SW,   //Selector modo zoom
	iEXPOSURE_ADJ,	  //|
	iEXPOSURE_DEC_p, //|Ajuste de exposición
	I2C_SCLK,		  //Reloj I2C
	I2C_SDAT			  //Dato I2C
	);
//---------------------------------------------------------------------------------
//I/O
//---------------------------------------------------------------------------------
input		iCLK;
input		iRST_N;
input 	iZOOM_MODE_SW;
output	I2C_SCLK;
inout		I2C_SDAT;
input 	iEXPOSURE_ADJ;
input		iEXPOSURE_DEC_p;
//---------------------------------------------------------------------------------
//Registros y señales
//---------------------------------------------------------------------------------
reg	[15:0]	mI2C_CLK_DIV;
reg	[31:0]	mI2C_DATA;
reg				mI2C_CTRL_CLK;
reg				mI2C_GO;
wire				mI2C_END;
wire				mI2C_ACK;
reg	[23:0]	LUT_DATA;
reg	[ 5:0]	LUT_INDEX;
reg	[ 3:0]	mSetup_ST;
reg	[24:0]	combo_cnt;
wire				combo_pulse;
reg	[1:0]		izoom_mode_sw_delay;
reg	[3:0]		iexposure_adj_delay;
wire				exposure_adj_set;	
wire				exposure_adj_reset;
reg	[15:0]	senosr_exposure;
wire  [23:0] 	sensor_start_row;
wire  [23:0] 	sensor_start_column;
wire  [23:0] 	sensor_row_size;
wire  [23:0] 	sensor_column_size; 
wire  [23:0] 	sensor_row_mode;
wire  [23:0] 	sensor_column_mode;
//---------------------------------------------------------------------------------
//Constantes
//---------------------------------------------------------------------------------
parameter 	default_exposure 			= 16'h07c0;
parameter 	exposure_change_value	 	= 16'd200;
//---------------------------------------------------------------------------------
//Configuración de zoom y exposición
//---------------------------------------------------------------------------------
assign sensor_start_row 		= iZOOM_MODE_SW ?  24'h010036 : 24'h010000;
assign sensor_start_column 	= iZOOM_MODE_SW ?  24'h020010 : 24'h020000;
assign sensor_row_size	 		= iZOOM_MODE_SW ?  24'h0303BF : 24'h03077F;
assign sensor_column_size 		= iZOOM_MODE_SW ?  24'h0404FF : 24'h0409FF;
assign sensor_row_mode 			= iZOOM_MODE_SW ?  24'h220000 : 24'h220011;
assign sensor_column_mode		= iZOOM_MODE_SW ?  24'h230000 : 24'h230011;

always@(posedge iCLK or negedge iRST_N)
	begin
		if (!iRST_N)
			begin
				iexposure_adj_delay <= 0;
			end
		else 
			begin
				iexposure_adj_delay <= {iexposure_adj_delay[2:0],iEXPOSURE_ADJ};		
			end	
	end

assign 	exposure_adj_set = ({iexposure_adj_delay[0],iEXPOSURE_ADJ}==2'b10) ? 1 : 0 ;
assign  exposure_adj_reset = ({iexposure_adj_delay[3:2]}==2'b10) ? 1 : 0 ;		

always@(posedge iCLK or negedge iRST_N)
	begin
		if (!iRST_N)
			senosr_exposure <= default_exposure;
		else if (exposure_adj_set|combo_pulse)
			begin
				if (iEXPOSURE_DEC_p)
					begin
						if ((senosr_exposure < exposure_change_value)||
							(senosr_exposure == 16'h0))
							senosr_exposure <= 0;
						else	
							senosr_exposure <= senosr_exposure - exposure_change_value;
					end		
				else
					begin
						if (((16'hffff -senosr_exposure) <exposure_change_value)||
							(senosr_exposure == 16'hffff))
							senosr_exposure <= 16'hffff;
						else
							senosr_exposure <= senosr_exposure + exposure_change_value;	
					end		
			end
	end			
		
always@(posedge iCLK or negedge iRST_N)
	begin
		if (!iRST_N)
			combo_cnt <= 0;
		else if (!iexposure_adj_delay[3])
			combo_cnt <= combo_cnt + 1;
		else
			combo_cnt <= 0;	
	end
	
assign combo_pulse = (combo_cnt == 25'h1fffff) ? 1 : 0;				
wire	 i2c_reset;		
assign i2c_reset = iRST_N & ~exposure_adj_reset & ~combo_pulse ;

//---------------------------------------------------------------------------------
//I2C Config
//---------------------------------------------------------------------------------
parameter	CLK_Freq	=	50000000;	//	50	MHz
parameter	I2C_Freq	=	20000;		//	20	KHz
parameter	LUT_SIZE	=	25;
//---------------------------------------------------------------------------------
//I2C Control Clock
//---------------------------------------------------------------------------------
always@(posedge iCLK or negedge i2c_reset)
begin
	if(!i2c_reset)
	begin
		mI2C_CTRL_CLK	<=	0;
		mI2C_CLK_DIV	<=	0;
	end
	else
	begin
		if( mI2C_CLK_DIV	< (CLK_Freq/I2C_Freq) )
		mI2C_CLK_DIV	<=	mI2C_CLK_DIV+1;
		else
		begin
			mI2C_CLK_DIV	<=	0;
			mI2C_CTRL_CLK	<=	~mI2C_CTRL_CLK;
		end
	end
end
//---------------------------------------------------------------------------------
//Componente I2C_Controller
//---------------------------------------------------------------------------------
I2C_Controller 	u0	(	.CLOCK(mI2C_CTRL_CLK),		//	Controller Work Clock
						.I2C_SCLK(I2C_SCLK),		//	I2C CLOCK
 	 	 	 	 	 	.I2C_SDAT(I2C_SDAT),		//	I2C DATA
						.I2C_DATA(mI2C_DATA),		//	DATA:[SLAVE_ADDR,SUB_ADDR,DATA]
						.GO(mI2C_GO),      			//	GO transfor
						.END(mI2C_END),				//	END transfor 
						.ACK(mI2C_ACK),				//	ACK
						.RESET(i2c_reset)
					);

always@(posedge mI2C_CTRL_CLK or negedge i2c_reset)
begin
	if(!i2c_reset)
	begin
		LUT_INDEX	<=	0;
		mSetup_ST	<=	0;
		mI2C_GO		<=	0;
	end
	else if(LUT_INDEX<LUT_SIZE)
		begin
			case(mSetup_ST)
			0:	begin
					mI2C_DATA	<=	{8'hBA,LUT_DATA};
					mI2C_GO		<=	1;
					mSetup_ST	<=	1;
				end
			1:	begin
					if(mI2C_END)
					begin
						if(!mI2C_ACK)
						mSetup_ST	<=	2;
						else
						mSetup_ST	<=	0;							
						mI2C_GO		<=	0;
					end
				end
			2:	begin
					LUT_INDEX	<=	LUT_INDEX+1;
					mSetup_ST	<=	0;
				end
			endcase
		end
end
//---------------------------------------------------------------------------------
// Datos de configuración I2C
//---------------------------------------------------------------------------------	
always
begin
	case(LUT_INDEX)
	0	:	LUT_DATA	<=	24'h000000;
	1	:	LUT_DATA	<=	24'h20c000;				//	Modo espejo
	2	:	LUT_DATA	<=	{8'h09,senosr_exposure};//	Exposición
	3	:	LUT_DATA	<=	24'h050000;				//	H_Blanking
	4	:	LUT_DATA	<=	24'h060019;				//	V_Blanking	
	5	:	LUT_DATA	<=	24'h0A8000;				//	Cambio latch
	6	:	LUT_DATA	<=	24'h2B000b;				//	Ganancia Verde 1
	7	:	LUT_DATA	<=	24'h2C000f;				//	Ganancia Azul
	8	:	LUT_DATA	<=	24'h2D000f;				//	Ganancia Rojo
	9	:	LUT_DATA	<=	24'h2E000b;				//	Ganancia Verde 2
	10	:	LUT_DATA	<=	24'h100051;				//	Activar PLL
	11	:	LUT_DATA	<=	24'h111807;				//	PLL_m_Factor<<8+PLL_n_Divider
	12	:	LUT_DATA	<=	24'h120002;				//	PLL_p1_Divider
	13	:	LUT_DATA	<=	24'h100053;				//	Control Uso PLL
	14	:	LUT_DATA	<=	24'h980000;				//	Deshabilitar calibración
`ifdef ENABLE_TEST_PATTERN
	15	:	LUT_DATA	<=	24'hA00001;				//	Test pattern control 	
	16	:	LUT_DATA	<=	24'hA10123;				//	Test green pattern value
	17	:	LUT_DATA	<=	24'hA20456;				//	Test red pattern value
`else
	15	:	LUT_DATA	<=	24'hA00000;				//	Test pattern control 
	16	:	LUT_DATA	<=	24'hA10000;				//	Test green pattern value
	17	:	LUT_DATA	<=	24'hA20FFF;				//	Test red pattern value
`endif
//---------------------------------------------------------------------------------
//Ajuste de resolución
//---------------------------------------------------------------------------------
	18	:	LUT_DATA	<=	sensor_start_row;		//	Dirección inicial de filas
	19	:	LUT_DATA	<=	sensor_start_column;	//	Dirección inicial columnas	
	20	:	LUT_DATA	<=	sensor_row_size;		//	Tamaño filas
	21	:	LUT_DATA	<=	sensor_column_size;	//	Tamaño columnas
	22	:	LUT_DATA	<=	sensor_row_mode;		//	Selector modo de filas
	23	:	LUT_DATA	<=	sensor_column_mode;	//	Selector modo de columnas
	24	:	LUT_DATA	<=	24'h4901A8;				//		
	default:LUT_DATA	<=	24'h000000;
	endcase
end
//---------------------------------------------------------------------------------
endmodule